package main

// TODO: прототип, в разработке

import (
	"encoding/json"
	"io/ioutil"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestScriptManager(t *testing.T) {
	// Создаем временную директорию для тестов
	tempDir, err := ioutil.TempDir("", "script_manager_test")
	if err != nil {
		t.Fatalf("Не удалось создать временную директорию: %v", err)
	}
	defer os.RemoveAll(tempDir)

	t.Run("TestNormalExecution", func(t *testing.T) {
		testNormalExecution(t, tempDir)
	})

	t.Run("TestResumeAfterFailure", func(t *testing.T) {
		testResumeAfterFailure(t, tempDir)
	})

	t.Run("TestCorruptedState", func(t *testing.T) {
		testCorruptedState(t, tempDir)
	})

	t.Run("TestEmptyScripts", func(t *testing.T) {
		testEmptyScripts(t, tempDir)
	})
}

func testNormalExecution(t *testing.T, baseDir string) {
	testDir := filepath.Join(baseDir, "normal_exec")
	os.MkdirAll(testDir, 0755)

	// Создаем тестовые скрипты
	scripts := []struct {
		name    string
		content string
	}{
		{"001_script.sh", `#!/bin/bash
echo "Script 1 executed"
exit 0
`},
		{"002_script.sh", `#!/bin/bash
echo "Script 2 executed"
exit 0
`},
		{"003_script.sh", `#!/bin/bash
echo "Script 3 executed"
exit 0
`},
	}

	for _, script := range scripts {
		scriptPath := filepath.Join(testDir, script.name)
		if err := ioutil.WriteFile(scriptPath, []byte(script.content), 0755); err != nil {
			t.Fatalf("Не удалось создать скрипт %s: %v", script.name, err)
		}
	}

	manager := NewScriptManager(testDir, false, false)

	if err := manager.Run(); err != nil {
		t.Errorf("Неожиданная ошибка при выполнении: %v", err)
	}

	// Проверяем, что состояние очищено после успешного выполнения
	stateFile := filepath.Join(testDir, "state.json")
	if _, err := os.Stat(stateFile); !os.IsNotExist(err) {
		t.Error("Файл состояния не был удален после успешного выполнения")
	}
}

func testResumeAfterFailure(t *testing.T, baseDir string) {
	testDir := filepath.Join(baseDir, "resume_test")
	os.MkdirAll(testDir, 0755)

	// Создаем скрипты, где второй скрипт будет падать
	scripts := []struct {
		name    string
		content string
	}{
		{"001_script.sh", `#!/bin/bash
echo "Script 1 executed successfully"
exit 0
`},
		{"002_script.sh", `#!/bin/bash
echo "Script 2 will fail"
exit 1
`},
		{"003_script.sh", `#!/bin/bash
echo "Script 3 should not be executed in first run"
exit 0
`},
	}

	for _, script := range scripts {
		scriptPath := filepath.Join(testDir, script.name)
		if err := ioutil.WriteFile(scriptPath, []byte(script.content), 0755); err != nil {
			t.Fatalf("Не удалось создать скрипт %s: %v", script.name, err)
		}
	}

	// Первый запуск - должен упасть на втором скрипте
	manager1 := NewScriptManager(testDir, false, false)
	err := manager1.Run()
	if err == nil {
		t.Error("Ожидалась ошибка при выполнении, но ее не было")
	}

	// Проверяем, что состояние сохранено
	stateFile := filepath.Join(testDir, "state.json")
	if _, err := os.Stat(stateFile); os.IsNotExist(err) {
		t.Fatal("Файл состояния не был создан после ошибки")
	}

	// Читаем состояние
	stateData, err := ioutil.ReadFile(stateFile)
	if err != nil {
		t.Fatalf("Не удалось прочитать файл состояния: %v", err)
	}

	var state ScriptState
	if err := json.Unmarshal(stateData, &state); err != nil {
		t.Fatalf("Не удалось распарсить состояние: %v", err)
	}

	if state.FailedScript != "002_script.sh" {
		t.Errorf("Ожидался failed_script=002_script.sh, получен %s", state.FailedScript)
	}

	if state.ExecutionStatus != StatusFailed {
		t.Errorf("Ожидался статус %s, получен %s", StatusFailed, state.ExecutionStatus)
	}

	// Исправляем падающий скрипт
	fixedScript := `#!/bin/bash
echo "Script 2 fixed and executed"
exit 0
`
	scriptPath := filepath.Join(testDir, "002_script.sh")
	if err := ioutil.WriteFile(scriptPath, []byte(fixedScript), 0755); err != nil {
		t.Fatalf("Не удалось исправить скрипт: %v", err)
	}

	// Второй запуск - должен продолжить с третьего скрипта
	manager2 := NewScriptManager(testDir, false, false)
	if err := manager2.Run(); err != nil {
		t.Errorf("Ошибка при повторном запуске: %v", err)
	}

	// Проверяем, что все скрипты выполнены
	if _, err := os.Stat(stateFile); !os.IsNotExist(err) {
		t.Error("Файл состояния не был удален после успешного выполнения")
	}
}

func testCorruptedState(t *testing.T, baseDir string) {
	testDir := filepath.Join(baseDir, "corrupted_test")
	os.MkdirAll(testDir, 0755)

	// Создаем простой скрипт
	scriptContent := `#!/bin/bash
echo "Test script"
exit 0
`
	scriptPath := filepath.Join(testDir, "001_script.sh")
	if err := ioutil.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		t.Fatalf("Не удалось создать скрипт: %v", err)
	}

	// Создаем поврежденный файл состояния
	corruptedState := `{"version": "1.1", "invalid_json`
	stateFile := filepath.Join(testDir, "state.json")
	if err := ioutil.WriteFile(stateFile, []byte(corruptedState), 0644); err != nil {
		t.Fatalf("Не удалось создать поврежденный файл состояния: %v", err)
	}

	// Тестируем в нестрогом режиме - должен продолжить работу
	manager := NewScriptManager(testDir, false, false)
	if err := manager.Run(); err != nil {
		t.Errorf("Неожиданная ошибка при поврежденном состоянии в нестрогом режиме: %v", err)
	}

	// Тестируем в строгом режиме - должен вернуть ошибку
	if err := ioutil.WriteFile(stateFile, []byte(corruptedState), 0644); err != nil {
		t.Fatalf("Не удалось пересоздать поврежденный файл состояния: %v", err)
	}

	managerStrict := NewScriptManager(testDir, false, true)
	err := managerStrict.Run()
	if err == nil {
		t.Error("Ожидалась ошибка при поврежденном состоянии в строгом режиме")
	}
}

func testEmptyScripts(t *testing.T, baseDir string) {
	testDir := filepath.Join(baseDir, "empty_test")
	os.MkdirAll(testDir, 0755)

	manager := NewScriptManager(testDir, false, false)
	err := manager.Run()

	if err == nil {
		t.Error("Ожидалась ошибка при отсутствии скриптов")
	}

	expectedError := "скрипты не найдены"
	if err.Error() != expectedError {
		t.Errorf("Ожидалась ошибка '%s', получена '%v'", expectedError, err)
	}
}

func TestStateIntegrity(t *testing.T) {
	tempDir, err := ioutil.TempDir("", "state_integrity_test")
	if err != nil {
		t.Fatalf("Не удалось создать временную директорию: %v", err)
	}
	defer os.RemoveAll(tempDir)

	manager := NewScriptManager(tempDir, false, true)

	// Тестируем сохранение состояния
	manager.state.ExecutionStatus = StatusRunning
	manager.state.CurrentScript = "test_script.sh"

	if err := manager.saveStateInternal(); err != nil {
		t.Errorf("Ошибка при сохранении состояния: %v", err)
	}

	// Проверяем целостность
	if err := manager.verifyStateIntegrity(); err != nil {
		t.Errorf("Ошибка проверки целостности: %v", err)
	}

	// Повреждаем файл состояния
	stateFile := filepath.Join(tempDir, "state.json")
	corruptedContent := `{"version": "1.1", "checksum": "999"}`
	if err := ioutil.WriteFile(stateFile, []byte(corruptedContent), 0644); err != nil {
		t.Fatalf("Не удалось повредить файл состояния: %v", err)
	}

	// Проверяем, что целостность нарушена
	if err := manager.verifyStateIntegrity(); err == nil {
		t.Error("Ожидалась ошибка при проверке целостности поврежденного файла")
	}
}

func TestSignalHandling(t *testing.T) {
	tempDir, err := ioutil.TempDir("", "signal_test")
	if err != nil {
		t.Fatalf("Не удалось создать временную директорию: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Создаем долгий скрипт
	longScript := `#!/bin/bash
echo "Starting long script"
sleep 10
echo "Script finished"
exit 0
`
	scriptPath := filepath.Join(tempDir, "001_script.sh")
	if err := ioutil.WriteFile(scriptPath, []byte(longScript), 0755); err != nil {
		t.Fatalf("Не удалось создать скрипт: %v", err)
	}

	manager := NewScriptManager(tempDir, false, false)

	// Запускаем менеджер в горутине
	done := make(chan error, 1)
	go func() {
		done <- manager.Run()
	}()

	// Даем время на старт
	time.Sleep(100 * time.Millisecond)

	// Отправляем сигнал прерывания
	manager.signals <- os.Interrupt

	// Ждем завершения
	select {
	case err := <-done:
		if err != nil {
			t.Logf("Менеджер завершился с ошибкой (ожидаемо): %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Error("Менеджер не завершился после сигнала")
	}

	// Проверяем, что состояние сохранено
	stateFile := filepath.Join(tempDir, "state.json")
	if _, err := os.Stat(stateFile); os.IsNotExist(err) {
		t.Error("Файл состояния не был создан после прерывания")
	} else {
		stateData, err := ioutil.ReadFile(stateFile)
		if err != nil {
			t.Fatalf("Не удалось прочитать файл состояния: %v", err)
		}

		var state ScriptState
		if err := json.Unmarshal(stateData, &state); err != nil {
			t.Fatalf("Не удалось распарсить состояние: %v", err)
		}

		if state.ExecutionStatus != StatusInterrupted {
			t.Errorf("Ожидался статус %s, получен %s", StatusInterrupted, state.ExecutionStatus)
		}
	}
}
