package main

import (
	"fmt"
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

	fmt.Println("Read", data, "bytes")
}
