package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

// Response represents the JSON response structure
type Response struct {
	Service   string    `json:"service"`
	Version   string    `json:"version"`
	Timestamp time.Time `json:"timestamp"`
	Region    string    `json:"region"`
	Message   string    `json:"message"`
}

// HealthResponse represents the health check response
type HealthResponse struct {
	Status    string    `json:"status"`
	Timestamp time.Time `json:"timestamp"`
}

// SecretResponse represents the secret retrieval response
type SecretResponse struct {
	Status  string `json:"status"`
	Secret  string `json:"secret"`
	Message string `json:"message"`
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-east-1"
	}

	http.HandleFunc("/", rootHandler(region))
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/secret", secretHandler(region))

	log.Printf("Stratum service starting on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func rootHandler(region string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)

		response := Response{
			Service:   "stratum-service",
			Version:   "1.1.0",
			Timestamp: time.Now().UTC(),
			Region:    region,
			Message:   "Stratum Retail Group — Platform Service",
		}

		json.NewEncoder(w).Encode(response)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	response := HealthResponse{
		Status:    "healthy",
		Timestamp: time.Now().UTC(),
	}

	json.NewEncoder(w).Encode(response)
}

func secretHandler(region string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		ctx := context.Background()

		cfg, err := config.LoadDefaultConfig(ctx,
			config.WithRegion(region),
		)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			json.NewEncoder(w).Encode(SecretResponse{
				Status:  "error",
				Message: "Failed to load AWS config: " + err.Error(),
			})
			return
		}

		client := secretsmanager.NewFromConfig(cfg)

		secretName := os.Getenv("SECRET_NAME")
		if secretName == "" {
			secretName = "stratum/platform/app-config"
		}

		result, err := client.GetSecretValue(ctx,
			&secretsmanager.GetSecretValueInput{
				SecretId: &secretName,
			})
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			json.NewEncoder(w).Encode(SecretResponse{
				Status:  "error",
				Message: "Failed to retrieve secret: " + err.Error(),
			})
			return
		}

		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(SecretResponse{
			Status:  "success",
			Secret:  "retrieved",
			Message: fmt.Sprintf("Secret length: %d characters. IRSA working correctly.", len(*result.SecretString)),
		})
	}
}