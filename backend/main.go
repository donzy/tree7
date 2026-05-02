package main

import (
	"fmt"
	"log"
	"net/http"
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

type HealthResponse struct {
	Status        string `json:"status"`
	Service       string `json:"service"`
	Model         string `json:"model"`
	ModelReady    bool   `json:"model_ready"`
	ModelsDir     string `json:"models_dir,omitempty"`
	LastError     string `json:"last_error,omitempty"`
}

var (
	ttsMutex    sync.Mutex
	tts         *sherpa.OfflineTts
	modelsDir   string
	lastInitErr string
)

func getModelsDir() string {
	if modelsDir != "" {
		return modelsDir
	}
	modelsDir = os.Getenv("MODELS_DIR")
	if modelsDir == "" {
		wd, _ := os.Getwd()
		modelsDir = filepath.Join(wd, "..", "models")
	}
	return modelsDir
}

func logMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		method := c.Request.Method
		
		log.Printf("[REQUEST] %s %s - Start", method, path)
		
		c.Next()
		
		latency := time.Since(start)
		status := c.Writer.Status()
		
		log.Printf("[REQUEST] %s %s - Status: %d, Duration: %v", method, path, status, latency)
	}
}

func errorMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Next()
		
		if len(c.Errors) > 0 {
			for _, e := range c.Errors {
				log.Printf("[ERROR] %v", e.Err)
			}
		}
	}
}

func initTTS() error {
	mDir := getModelsDir()
	log.Printf("[INIT] Models directory: %s", mDir)
	
	config := sherpa.OfflineTtsConfig{}
	
	modelPath := filepath.Join(mDir, "kokoro", "model.onnx")
	voicesPath := filepath.Join(mDir, "kokoro", "voices.bin")
	tokensPath := filepath.Join(mDir, "kokoro", "tokens.txt")
	espeakDir := filepath.Join(mDir, "espeak-ng-data")
	lexiconZh := filepath.Join(mDir, "kokoro", "lexicon-zh.txt")
	lexiconEn := filepath.Join(mDir, "kokoro", "lexicon-us-en.txt")
	
	log.Printf("[INIT] Checking model files...")
	
	if _, err := os.Stat(modelPath); os.IsNotExist(err) {
		lastInitErr = fmt.Sprintf("model file not found: %s", modelPath)
		return fmt.Errorf("%s. Please run scripts/download_models.sh", lastInitErr)
	}
	log.Printf("[INIT] ✓ Model: %s", modelPath)
	
	if _, err := os.Stat(voicesPath); os.IsNotExist(err) {
		log.Printf("[INIT] ⚠ Voices file not found: %s", voicesPath)
	} else {
		log.Printf("[INIT] ✓ Voices: %s", voicesPath)
	}
	
	if _, err := os.Stat(tokensPath); os.IsNotExist(err) {
		log.Printf("[INIT] ⚠ Tokens file not found: %s", tokensPath)
	} else {
		log.Printf("[INIT] ✓ Tokens: %s", tokensPath)
	}
	
	if _, err := os.Stat(espeakDir); os.IsNotExist(err) {
		log.Printf("[INIT] ⚠ eSpeak data dir not found: %s", espeakDir)
	} else {
		log.Printf("[INIT] ✓ eSpeak: %s", espeakDir)
	}
	
	config.Model.Kokoro.Model = modelPath
	config.Model.Kokoro.Voices = voicesPath
	config.Model.Kokoro.Tokens = tokensPath
	config.Model.Kokoro.DataDir = espeakDir
	config.Model.Kokoro.Lexicon = lexiconZh + "," + lexiconEn
	config.Model.Kokoro.LengthScale = 1.0
	
	config.Model.NumThreads = 4
	config.Model.Debug = 1
	config.Model.Provider = "cpu"
	
	config.MaxNumSentences = 1
	
	log.Println("[INIT] Initializing TTS model (may take several seconds)...")
	tts = sherpa.NewOfflineTts(&config)
	if tts == nil {
		lastInitErr = "failed to create TTS model (sherpa.NewOfflineTts returned nil)"
		return fmt.Errorf(lastInitErr)
	}
	
	log.Println("[INIT] ✓ TTS model initialized successfully")
	log.Printf("[INIT] Sample rate: %d", tts.SampleRate())
	lastInitErr = ""
	
	return nil
}

func generateSpeech(text string, voice int, speed float32) (string, error) {
	ttsMutex.Lock()
	defer ttsMutex.Unlock()
	
	if tts == nil {
		return "", fmt.Errorf("TTS model not initialized. Last error: %s", lastInitErr)
	}
	
	if speed <= 0 {
		speed = 1.0
	}
	
	log.Printf("[TTS] Generating speech: voice=%d, speed=%.1f, text=%q", voice, speed, text)
	
	cfg := sherpa.GenerationConfig{
		SilenceScale: 0.2,
		Speed:        speed,
		Sid:          voice,
	}
	
	start := time.Now()
	generated := tts.GenerateWithConfig(text, &cfg, func(samples []float32, progress float32) bool {
		log.Printf("[TTS] Progress: %.1f%%, samples: %d", progress*100, len(samples))
		return true
	})
	
	if generated == nil {
		return "", fmt.Errorf("failed to generate speech (model returned nil)")
	}
	
	elapsed := time.Since(start)
	log.Printf("[TTS] Speech generated in %v", elapsed)
	
	audioDir := "./audio"
	if err := os.MkdirAll(audioDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create audio directory: %w", err)
	}
	
	filename := fmt.Sprintf("tts_%d.wav", time.Now().UnixNano())
	filepath := filepath.Join(audioDir, filename)
	
	if ok := generated.Save(filepath); !ok {
		return "", fmt.Errorf("failed to save audio file to %s", filepath)
	}
	
	fileInfo, err := os.Stat(filepath)
	if err != nil {
		log.Printf("[TTS] Warning: could not get file info: %v", err)
	} else {
		log.Printf("[TTS] Audio saved: %s (%d bytes)", filepath, fileInfo.Size())
	}
	
	return filename, nil
}

func handleTTS(c *gin.Context) {
	var req TTSRequest
	
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("[TTS] Invalid request: %v", err)
		c.JSON(http.StatusBadRequest, TTSResponse{
			Success: false,
			Message: "Invalid request: " + err.Error(),
		})
		return
	}
	
	req.Text = strings.TrimSpace(req.Text)
	if req.Text == "" {
		log.Printf("[TTS] Empty text provided")
		c.JSON(http.StatusBadRequest, TTSResponse{
			Success: false,
			Message: "Text cannot be empty",
		})
		return
	}
	
	filename, err := generateSpeech(req.Text, req.Voice, req.Speed)
	if err != nil {
		log.Printf("[TTS] Error: %v", err)
		c.JSON(http.StatusInternalServerError, TTSResponse{
			Success: false,
			Message: err.Error(),
		})
		return
	}
	
	audioURL := fmt.Sprintf("/audio/%s", filename)
	log.Printf("[TTS] Success! Audio URL: %s", audioURL)
	
	c.JSON(http.StatusOK, TTSResponse{
		Success:  true,
		AudioURL: audioURL,
	})
}

func handleHealth(c *gin.Context) {
	modelReady := tts != nil
	mDir := getModelsDir()
	
	response := HealthResponse{
		Status:     "ok",
		Service:    "tree7-tts",
		Model:      "kokoro-82m",
		ModelReady: modelReady,
		ModelsDir:  mDir,
	}
	
	if !modelReady && lastInitErr != "" {
		response.LastError = lastInitErr
	}
	
	c.JSON(http.StatusOK, response)
}

func handleOptions(c *gin.Context) {
	c.Header("Access-Control-Allow-Origin", "*")
	c.Header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE")
	c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization")
	c.Header("Access-Control-Max-Age", "86400")
	c.Status(http.StatusNoContent)
}

func main() {
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)
	
	log.Println("========================================")
	log.Println("  Tree7 TTS Backend")
	log.Println("  Model: Kokoro-82M ONNX")
	log.Println("========================================")
	log.Println()
	
	if err := initTTS(); err != nil {
		log.Printf("[WARNING] Failed to initialize TTS model: %v", err)
		log.Println("[WARNING] The server will start, but TTS requests will fail.")
		log.Println("[WARNING] Please download model files using: scripts/download_models.sh")
	} else {
		log.Println("[OK] TTS model ready!")
	}
	log.Println()
	
	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(logMiddleware())
	r.Use(errorMiddleware())
	
	corsConfig := cors.DefaultConfig()
	corsConfig.AllowAllOrigins = true
	corsConfig.AllowMethods = []string{
		http.MethodGet,
		http.MethodPost,
		http.MethodPut,
		http.MethodDelete,
		http.MethodOptions,
	}
	corsConfig.AllowHeaders = []string{
		"Origin",
		"Content-Type",
		"Accept",
		"Authorization",
		"X-Requested-With",
	}
	corsConfig.ExposeHeaders = []string{
		"Content-Length",
		"Content-Type",
	}
	corsConfig.AllowCredentials = false
	corsConfig.MaxAge = 12 * time.Hour
	
	r.Use(cors.New(corsConfig))
	
	r.NoRoute(func(c *gin.Context) {
		if c.Request.Method == http.MethodOptions {
			handleOptions(c)
			return
		}
		c.JSON(http.StatusNotFound, gin.H{
			"success": false,
			"message": "Route not found",
		})
	})
	
	audioDir := "./audio"
	if err := os.MkdirAll(audioDir, 0755); err != nil {
		log.Printf("[WARNING] Failed to create audio directory: %v", err)
	}
	r.Static("/audio", audioDir)
	log.Printf("[CONFIG] Audio static directory: %s", audioDir)
	
	r.GET("/health", handleHealth)
	r.OPTIONS("/health", handleOptions)
	
	r.POST("/api/tts", handleTTS)
	r.OPTIONS("/api/tts", handleOptions)
	
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	
	log.Println()
	log.Println("========================================")
	log.Printf("  Server starting on port %s...", port)
	log.Println("========================================")
	log.Println()
	log.Println("API endpoints:")
	log.Printf("  GET  http://localhost:%s/health", port)
	log.Printf("  POST http://localhost:%s/api/tts", port)
	log.Printf("  GET  http://localhost:%s/audio/*", port)
	log.Println()
	log.Println("Press Ctrl+C to stop the server")
	log.Println()
	
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("[FATAL] Failed to start server: %v", err)
	}
}
