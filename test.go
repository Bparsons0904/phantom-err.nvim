package main

import (
	"fmt"
	"log/slog"
	"os"
)

func main() {
	file, err := os.Open("test.txt")
	if err != nil {
		fmt.Println("Error opening file:", err)
		return
	}
	defer file.Close()

	data, err := file.Read(make([]byte, 100))
	if err != nil {
		fmt.Println("Error reading file:", err)
		return
	}

	if err := processFile(file); err != nil {
		if os.IsNotExist(err) {
			fmt.Println("File does not exist")
			return
		}
		fmt.Printf("Processing failed: %v\n", err)
		return
	}

	if err := validateData(data); err != nil {
		fmt.Printf("Validation failed: %v\n", err)
		return
	}

	if err := saveResults(data); err != nil {
		slog.Error("Failed to save", "error", err)
		cleanup()
		return
	}

	fmt.Println("Read", data, "bytes")
}

func processFile(file *os.File) error {
	// Some processing logic
	return nil
}

func validateData(data int) error {
	// Some validation logic
	return nil
}

func saveResults(data int) error {
	// Some save logic
	return nil
}

func cleanup() {
	// Cleanup logic
}
