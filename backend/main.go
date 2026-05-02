package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	sherpa "github.com/k2-fsa/sherpa-onnx-go/sherpa_onnx"
)

type TTSRequest struct {
	Text  string  `json:"text" binding:"required"`
	Voice int     `json:"voice"`
	Speed float32 `json:"speed"`
}

type TTSResponse struct {
	Success  bool   `json:"success"`
	Message  string `json:"message,omitempty"`
	AudioURL string `json:"audio_url,omitempty"`
}

var (
	ttsMutex sync.Mutex
	tts      *sherpa.OfflineTts
)

func getModelsDir() string {
	modelsDir := os.Getenv("MODELS_DIR")
	if modelsDir == "" {
		wd, _ := os.Getwd()
		modelsDir = filepath.Join(wd, "..", "models")
	}
	return modelsDir
}

func initTTS() error {
	modelsDir := getModelsDir()
	
	config := sherpa.OfflineTtsConfig{}
	
	config.Model.Kokoro.Model = filepath.Join(modelsDir, "kokoro", "model.onnx")
	config.Model.Kokoro.Voices = filepath.Join(modelsDir, "kokoro", "voices.bin")
	config.Model.Kokoro.Tokens = filepath.Join(modelsDir, "kokoro", "tokens.txt")
	config.Model.Kokoro.DataDir = filepath.Join(modelsDir, "espeak-ng-data")
	config.Model.Kokoro.Lexicon = filepath.Join(modelsDir, "kokoro", "lexicon-zh.txt") + "," + 
		filepath.Join(modelsDir, "kokoro", "lexicon-us-en.txt")
	config.Model.Kokoro.LengthScale = 1.0
	
	config.Model.NumThreads = 4
	config.Model.Debug = 0
	config.Model.Provider = "cpu"
	
	config.MaxNumSentences = 1
	
	if _, err := os.Stat(config.Model.Kokoro.Model); os.IsNotExist(err) {
		return fmt.Errorf("model file not found: %s. Please download the Kokoro model first", config.Model.Kokoro.Model)
	}
	
	log.Println("Initializing TTS model (may take several seconds)...")
	tts = sherpa.NewOfflineTts(&config)
	if tts == nil {
		return fmt.Errorf("failed to create TTS model")
	}
	
	log.Println("TTS model initialized successfully")
	log.Printf("Sample rate: %d", tts.SampleRate())
	
	return nil
}

func generateSpeech(text string, voice int, speed float32) (string, error) {
	ttsMutex.Lock()
	defer ttsMutex.Unlock()
	
	if tts == nil {
		return "", fmt.Errorf("TTS not initialized")
	}
	
	if speed <= 0 {
		speed = 1.0
	}
	
	log.Printf("Generating speech for: %s (voice: %d, speed: %.1f)", text, voice, speed)
	
	cfg := sherpa.GenerationConfig{
		SilenceScale: 0.2,
		Speed:        speed,
		Sid:          voice,
	}
	
	start := time.Now()
	generated := tts.GenerateWithConfig(text, &cfg, func(samples []float32, progress float32) bool {
		log.Printf("Progress: %.1f%%", progress*100)
		return true
	})
	
	if generated == nil {
		return "", fmt.Errorf("failed to generate speech")
	}
	
	log.Printf("Speech generated in %v", time.Since(start))
	
	audioDir := "./audio"
	if err := os.MkdirAll(audioDir, 0755); err != nil {
		return "", err
	}
	
	filename := fmt.Sprintf("tts_%d.wav", time.Now().UnixNano())
	filepath := filepath.Join(audioDir, filename)
	
	if ok := generated.Save(filepath); !ok {
		return "", fmt.Errorf("failed to save audio file")
	}
	
	log.Printf("Audio saved to: %s", filepath)
	return filename, nil
}

func handleTTS(c *gin.Context) {
	var req TTSRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, TTSResponse{
			Success: false,
			Message: "Invalid request body: " + err.Error(),
		})
		return
	}
	
	req.Text = strings.TrimSpace(req.Text)
	if req.Text == "" {
		c.JSON(400, TTSResponse{
			Success: false,
			Message: "Text cannot be empty",
		})
		return
	}
	
	filename, err := generateSpeech(req.Text, req.Voice, req.Speed)
	if err != nil {
		log.Printf("TTS error: %v", err)
		c.JSON(500, TTSResponse{
			Success: false,
			Message: "Failed to generate speech: " + err.Error(),
		})
		return
	}
	
	audioURL := fmt.Sprintf("/audio/%s", filename)
	c.JSON(200, TTSResponse{
		Success:  true,
		AudioURL: audioURL,
	})
}

func handleHealth(c *gin.Context) {
	c.JSON(200, gin.H{
		"status":  "ok",
		"service": "tree7-tts",
		"model":   "kokoro-82m",
	})
}

func main() {
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)
	
	if err := initTTS(); err != nil {
		log.Printf("Warning: Failed to initialize TTS: %v", err)
		log.Printf("Please download the model files and run again")
	}
	
	r := gin.Default()
	
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"},
		AllowMethods:     []string{"GET", "POST", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Accept"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
	}))
	
	r.Static("/audio", "./audio")
	
	r.GET("/health", handleHealth)
	r.POST("/api/tts", handleTTS)
	
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	
	log.Printf("Server starting on port %s...", port)
	log.Printf("API endpoints:")
	log.Printf("  GET  /health     - Health check")
	log.Printf("  POST /api/tts    - Text to speech")
	log.Printf("  GET  /audio/*    - Audio files")
	
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
