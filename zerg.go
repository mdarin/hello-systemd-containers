package main

// TODO: прототип, в разработке

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime/debug"
	"sort"
	"sync/atomic"
	"syscall"
	"time"
)

type ExecutionStatus string

const (
	StatusPending     ExecutionStatus = "pending"
	StatusRunning     ExecutionStatus = "running"
	StatusCompleted   ExecutionStatus = "completed"
	StatusFailed      ExecutionStatus = "failed"
	StatusInterrupted ExecutionStatus = "interrupted"
)

type ScriptExecution struct {
	ScriptName string          `json:"script_name"`
	Status     ExecutionStatus `json:"status"`
	StartTime  time.Time       `json:"start_time,omitempty"`
	EndTime    time.Time       `json:"end_time,omitempty"`
	Duration   time.Duration   `json:"duration,omitempty"`
	Error      string          `json:"error,omitempty"`
}

type ScriptState struct {
	Version         string            `json:"version"`
	StartTime       time.Time         `json:"start_time"`
	LastUpdate      time.Time         `json:"last_update"`
	SessionID       string            `json:"session_id"`
	CurrentScript   string            `json:"current_script,omitempty"`
	ExecutionStatus ExecutionStatus   `json:"execution_status"`
	Completed       []string          `json:"completed_scripts"`
	Executions      []ScriptExecution `json:"executions"`
	FailedScript    string            `json:"failed_script,omitempty"`
	ErrorCount      int               `json:"error_count"`
	Checksum        string            `json:"checksum,omitempty"`
}

type ScriptManager struct {
	scriptsDir     string
	stateFile      string
	stateFileTemp  string
	verbose        bool
	strictMode     bool
	state          *ScriptState
	isShuttingDown atomic.Bool
	currentScript  string
	signals        chan os.Signal
}

func NewScriptManager(scriptsDir string, verbose, strict bool) *ScriptManager {
	sessionID := fmt.Sprintf("%d", time.Now().UnixNano())
	tempFile := filepath.Join(scriptsDir, ".state.tmp")

	return &ScriptManager{
		scriptsDir:    scriptsDir,
		stateFile:     filepath.Join(scriptsDir, "state.json"),
		stateFileTemp: tempFile,
		verbose:       verbose,
		strictMode:    strict,
		state: &ScriptState{
			Version:         "1.1",
			StartTime:       time.Now(),
			LastUpdate:      time.Now(),
			SessionID:       sessionID,
			ExecutionStatus: StatusPending,
			Completed:       []string{},
			Executions:      []ScriptExecution{},
			ErrorCount:      0,
		},
		signals: make(chan os.Signal, 1),
	}
}

func (sm *ScriptManager) log(format string, args ...interface{}) {
	if sm.verbose {
		timestamp := time.Now().Format("2006-01-02 15:04:05")
		log.Printf("[%s] "+format, append([]interface{}{timestamp}, args...)...)
	}
}

func (sm *ScriptManager) setupSignalHandling() {
	signal.Notify(sm.signals, syscall.SIGINT, syscall.SIGTERM, syscall.SIGQUIT)

	go func() {
		sig := <-sm.signals
		sm.log("Получен сигнал: %v", sig)
		sm.handleGracefulShutdown(sig.String())
	}()
}

func (sm *ScriptManager) stopSignalHandling() {
	signal.Stop(sm.signals)
	close(sm.signals)
}

func (sm *ScriptManager) setupPanicRecovery() {
	if r := recover(); r != nil {
		sm.log("КРИТИЧЕСКИЙ СБОЙ: %v\n%s", r, debug.Stack())
		sm.handleCriticalFailure(fmt.Sprintf("Panic: %v", r))
		os.Exit(1)
	}
}

func (sm *ScriptManager) handleGracefulShutdown(reason string) {
	if sm.isShuttingDown.Swap(true) {
		return
	}

	sm.log("Начинаем graceful shutdown...")

	sm.state.ExecutionStatus = StatusInterrupted
	sm.state.LastUpdate = time.Now()

	if sm.currentScript != "" {
		for i := range sm.state.Executions {
			if sm.state.Executions[i].ScriptName == sm.currentScript &&
				sm.state.Executions[i].Status == StatusRunning {
				sm.state.Executions[i].Status = StatusInterrupted
				sm.state.Executions[i].EndTime = time.Now()
				sm.state.Executions[i].Duration = time.Since(sm.state.Executions[i].StartTime)
				sm.state.Executions[i].Error = fmt.Sprintf("Прервано сигналом: %s", reason)
				break
			}
		}
	}

	if err := sm.saveStateWithRetry(); err != nil {
		sm.log("ОШИБКА СОХРАНЕНИЯ СОСТОЯНИЯ ПРИ SHUTDOWN: %v", err)
	} else {
		sm.log("Состояние успешно сохранено при shutdown")
	}

	sm.stopSignalHandling()
	os.Exit(130)
}

func (sm *ScriptManager) handleCriticalFailure(errorMsg string) {
	sm.state.ExecutionStatus = StatusFailed
	sm.state.LastUpdate = time.Now()
	sm.state.ErrorCount++

	if sm.currentScript != "" {
		sm.state.FailedScript = sm.currentScript
		for i := range sm.state.Executions {
			if sm.state.Executions[i].ScriptName == sm.currentScript {
				sm.state.Executions[i].Status = StatusFailed
				sm.state.Executions[i].EndTime = time.Now()
				sm.state.Executions[i].Duration = time.Since(sm.state.Executions[i].StartTime)
				sm.state.Executions[i].Error = errorMsg
				break
			}
		}
	}

	sm.emergencySaveState()
}

func (sm *ScriptManager) emergencySaveState() {
	defer func() {
		if r := recover(); r != nil {
			fmt.Printf("CRITICAL: Не удалось сохранить состояние даже в аварийном режиме: %v\n", r)
		}
	}()

	if err := sm.saveStateInternal(); err != nil {
		sm.log("Аварийное сохранение (попытка 1 не удалась): %v", err)

		simpleState := map[string]interface{}{
			"emergency_save": time.Now().Format(time.RFC3339),
			"failed_script":  sm.state.FailedScript,
			"current_script": sm.currentScript,
			"last_update":    time.Now().Format(time.RFC3339),
			"error":          "critical_failure",
		}

		if data, err := json.Marshal(simpleState); err == nil {
			ioutil.WriteFile(sm.stateFile+".emergency", data, 0644)
		}

		simpleText := fmt.Sprintf("FAILED:%s\nSCRIPT:%s\nTIME:%s\n",
			sm.state.FailedScript, sm.currentScript, time.Now().Format(time.RFC3339))
		ioutil.WriteFile(sm.stateFile+".txt", []byte(simpleText), 0644)
	}
}

func (sm *ScriptManager) saveStateWithRetry() error {
	const maxRetries = 3
	var lastErr error

	for i := 0; i < maxRetries; i++ {
		if err := sm.saveStateInternal(); err != nil {
			lastErr = err
			sm.log("Попытка %d сохранения состояния не удалась: %v", i+1, err)
			time.Sleep(100 * time.Millisecond)
			continue
		}
		return nil
	}

	return fmt.Errorf("не удалось сохранить состояние после %d попыток: %v", maxRetries, lastErr)
}

func (sm *ScriptManager) saveStateInternal() error {
	sm.state.LastUpdate = time.Now()

	data, err := json.MarshalIndent(sm.state, "", "  ")
	if err != nil {
		return fmt.Errorf("ошибка маршалинга состояния: %v", err)
	}

	if sm.strictMode {
		sm.state.Checksum = fmt.Sprintf("%d", len(data))
		// Перемаршалируем с контрольной суммой
		data, err = json.MarshalIndent(sm.state, "", "  ")
		if err != nil {
			return fmt.Errorf("ошибка маршалинга с контрольной суммой: %v", err)
		}
	}

	if err := ioutil.WriteFile(sm.stateFileTemp, data, 0644); err != nil {
		return fmt.Errorf("ошибка записи временного файла: %v", err)
	}

	if err := os.Rename(sm.stateFileTemp, sm.stateFile); err != nil {
		return fmt.Errorf("ошибка переименования файла состояния: %v", err)
	}

	if sm.strictMode {
		if err := sm.verifyStateIntegrity(); err != nil {
			return fmt.Errorf("ошибка проверки целостности: %v", err)
		}
	}

	return nil
}

func (sm *ScriptManager) verifyStateIntegrity() error {
	data, err := ioutil.ReadFile(sm.stateFile)
	if err != nil {
		return err
	}

	var verifyState ScriptState
	if err := json.Unmarshal(data, &verifyState); err != nil {
		return fmt.Errorf("ошибка чтения сохраненного состояния: %v", err)
	}

	if verifyState.Checksum != fmt.Sprintf("%d", len(data)) {
		return fmt.Errorf("несовпадение контрольной суммы")
	}

	return nil
}

func (sm *ScriptManager) loadState() error {
	if _, err := os.Stat(sm.stateFile); os.IsNotExist(err) {
		sm.log("Файл состояния не существует, начинаем с начала")
		return nil
	}

	data, err := ioutil.ReadFile(sm.stateFile)
	if err != nil {
		return fmt.Errorf("ошибка чтения файла состояния: %v", err)
	}

	var savedState ScriptState
	if err := json.Unmarshal(data, &savedState); err != nil {
		return sm.handleCorruptedState(data)
	}

	if sm.strictMode && savedState.Checksum != fmt.Sprintf("%d", len(data)) {
		sm.log("Предупреждение: несовпадение контрольной суммы")
		return sm.handleCorruptedState(data)
	}

	sm.state = &savedState
	sm.log("Состояние загружено: сессия %s, статус %s", savedState.SessionID, savedState.ExecutionStatus)

	return nil
}

func (sm *ScriptManager) handleCorruptedState(data []byte) error {
	if !sm.strictMode {
		sm.log("Продолжаем с очищенным состоянием")
		return nil
	}

	backupFile := fmt.Sprintf("%s.corrupted.%d", sm.stateFile, time.Now().Unix())
	if err := ioutil.WriteFile(backupFile, data, 0644); err != nil {
		sm.log("Ошибка сохранения резервной копии поврежденного состояния: %v", err)
	}

	return fmt.Errorf("обнаружено поврежденное состояние, создана резервная копия: %s", backupFile)
}

func (sm *ScriptManager) getScripts() ([]string, error) {
	patterns := []string{"[0-9][0-9][0-9]*script.sh", "[0-9][0-9]*script.sh", "*script.sh"}
	var allScripts []string

	for _, pattern := range patterns {
		files, err := filepath.Glob(filepath.Join(sm.scriptsDir, pattern))
		if err != nil {
			return nil, err
		}
		allScripts = append(allScripts, files...)
	}

	uniqueScripts := make(map[string]bool)
	for _, script := range allScripts {
		uniqueScripts[script] = true
	}

	result := make([]string, 0, len(uniqueScripts))
	for script := range uniqueScripts {
		result = append(result, script)
	}

	sort.Strings(result)
	return result, nil
}

func (sm *ScriptManager) validateScript(scriptPath string) error {
	info, err := os.Stat(scriptPath)
	if err != nil {
		return fmt.Errorf("ошибка доступа к скрипту: %v", err)
	}

	if info.Size() == 0 {
		return fmt.Errorf("скрипт пустой")
	}

	if info.Size() > 10*1024*1024 {
		return fmt.Errorf("скрипт слишком большой: %d bytes", info.Size())
	}

	return nil
}

func (sm *ScriptManager) executeScript(scriptPath string) error {
	scriptName := filepath.Base(scriptPath)

	if err := sm.validateScript(scriptPath); err != nil {
		return fmt.Errorf("валидация скрипта не пройдена: %v", err)
	}

	if err := os.Chmod(scriptPath, 0755); err != nil {
		sm.log("Предупреждение: не удалось установить права на выполнение: %v", err)
	}

	cmd := exec.Command("bash", "-e", "-o", "pipefail", scriptPath)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Dir = sm.scriptsDir

	startTime := time.Now()
	err := cmd.Run()
	duration := time.Since(startTime)

	for i := range sm.state.Executions {
		if sm.state.Executions[i].ScriptName == scriptName {
			sm.state.Executions[i].EndTime = time.Now()
			sm.state.Executions[i].Duration = duration
			if err != nil {
				sm.state.Executions[i].Status = StatusFailed
				sm.state.Executions[i].Error = err.Error()
			} else {
				sm.state.Executions[i].Status = StatusCompleted
			}
			break
		}
	}

	return err
}

func (sm *ScriptManager) findResumePoint(scripts []string) int {
	if len(sm.state.Executions) == 0 {
		return 0
	}

	lastCompleted := ""
	for i := len(sm.state.Executions) - 1; i >= 0; i-- {
		if sm.state.Executions[i].Status == StatusCompleted {
			lastCompleted = sm.state.Executions[i].ScriptName
			break
		}
	}

	if lastCompleted == "" && sm.state.FailedScript != "" {
		lastCompleted = sm.state.FailedScript
	}

	if lastCompleted == "" {
		return 0
	}

	for i, script := range scripts {
		scriptName := filepath.Base(script)
		if scriptName == lastCompleted {
			if sm.state.ExecutionStatus == StatusFailed || sm.state.ExecutionStatus == StatusInterrupted {
				return i
			}
			return i + 1
		}
	}

	return 0
}

func (sm *ScriptManager) Run() error {
	defer sm.setupPanicRecovery()
	sm.setupSignalHandling()
	defer sm.stopSignalHandling()

	if err := sm.loadState(); err != nil {
		sm.handleCriticalFailure(fmt.Sprintf("loadState: %v", err))
		return fmt.Errorf("ошибка загрузки состояния: %v", err)
	}

	scripts, err := sm.getScripts()
	if err != nil {
		sm.handleCriticalFailure(fmt.Sprintf("getScripts: %v", err))
		return fmt.Errorf("ошибка получения списка скриптов: %v", err)
	}

	if len(scripts) == 0 {
		return fmt.Errorf("скрипты не найдены")
	}

	sm.log("Найдено скриптов: %d", len(scripts))

	startIndex := sm.findResumePoint(scripts)
	sm.log("Начинаем выполнение с индекса: %d", startIndex)

	sm.state.ExecutionStatus = StatusRunning
	if err := sm.saveStateWithRetry(); err != nil {
		sm.handleCriticalFailure(fmt.Sprintf("saveState initial: %v", err))
		return err
	}

	for i := startIndex; i < len(scripts); i++ {
		if sm.isShuttingDown.Load() {
			sm.log("Обнаружено завершение работы, прерываем выполнение")
			break
		}

		script := scripts[i]
		scriptName := filepath.Base(script)
		sm.currentScript = scriptName

		execution := ScriptExecution{
			ScriptName: scriptName,
			Status:     StatusRunning,
			StartTime:  time.Now(),
		}
		sm.state.Executions = append(sm.state.Executions, execution)
		sm.state.CurrentScript = scriptName

		fmt.Printf("\n🚀 [%d/%d] Выполнение: %s\n", i+1, len(scripts), scriptName)

		if err := sm.saveStateWithRetry(); err != nil {
			sm.handleCriticalFailure(fmt.Sprintf("saveState pre-execution: %v", err))
			return err
		}

		startTime := time.Now()
		err := sm.executeScript(script)
		duration := time.Since(startTime)

		if err != nil {
			sm.state.ExecutionStatus = StatusFailed
			sm.state.FailedScript = scriptName
			sm.state.ErrorCount++

			fmt.Printf("❌ Ошибка в скрипте %s (%v)\n", scriptName, duration)

			if saveErr := sm.saveStateWithRetry(); saveErr != nil {
				sm.handleCriticalFailure(fmt.Sprintf("saveState post-failure: %v", saveErr))
			}

			return fmt.Errorf("скрипт %s завершился с ошибкой: %v", scriptName, err)
		}

		sm.state.Completed = append(sm.state.Completed, scriptName)
		sm.state.CurrentScript = ""
		sm.currentScript = ""

		fmt.Printf("✅ Успешно выполнено за %v\n", duration)

		if err := sm.saveStateWithRetry(); err != nil {
			sm.handleCriticalFailure(fmt.Sprintf("saveState post-success: %v", err))
			return err
		}
	}

	if !sm.isShuttingDown.Load() {
		sm.state.ExecutionStatus = StatusCompleted
		sm.state.LastUpdate = time.Now()

		if err := sm.saveStateWithRetry(); err != nil {
			sm.log("Ошибка сохранения финального состояния: %v", err)
		}

		if err := os.Remove(sm.stateFile); err != nil && !os.IsNotExist(err) {
			sm.log("Предупреждение: не удалось удалить файл состояния: %v", err)
		}

		fmt.Printf("\n🎉 Все %d скриптов выполнены успешно!\n", len(scripts))
	}

	return nil
}

func main() {
	if len(os.Args) < 2 {
		fmt.Printf("Использование: %s <директория> [--verbose] [--strict]\n", os.Args[0])
		fmt.Printf("  --verbose  Подробное логирование\n")
		fmt.Printf("  --strict   Строгий режим с проверкой целостности\n")
		os.Exit(1)
	}

	scriptsDir := os.Args[1]
	verbose := false
	strict := false

	for _, arg := range os.Args[2:] {
		switch arg {
		case "--verbose":
			verbose = true
		case "--strict":
			strict = true
		}
	}

	if _, err := os.Stat(scriptsDir); os.IsNotExist(err) {
		log.Fatalf("❌ Директория %s не существует", scriptsDir)
	}

	manager := NewScriptManager(scriptsDir, verbose, strict)

	if err := manager.Run(); err != nil {
		log.Printf("❌ Завершено с ошибкой: %v", err)
		os.Exit(1)
	}
}
