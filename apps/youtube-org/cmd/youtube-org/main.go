package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"youtube-extractor/internal/capture"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	os.Exit(capture.Run(ctx, os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}
