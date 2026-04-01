package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type serverConfig struct {
	ListenAddr       string        `json:"listen_addr"`
	PublicBaseURL    string        `json:"public_base_url"`
	Provider         string        `json:"provider"`
	PanelURL         string        `json:"panel_url"`
	PanelDesc        string        `json:"panel_desc"`
	SubscriptionURL  string        `json:"subscription_url"`
	SubscriptionDesc string        `json:"subscription_desc"`
	AssetsDir        string        `json:"assets_dir"`
	ManifestPath     string        `json:"manifest_path"`
	CheckPath        string        `json:"check_path"`
	ConfigPath       string        `json:"config_path"`
	FilesPath        string        `json:"files_path"`
	ReadTimeout      time.Duration `json:"-"`
	WriteTimeout     time.Duration `json:"-"`
}

type rawConfig struct {
	ListenAddr       string `json:"listen_addr"`
	PublicBaseURL    string `json:"public_base_url"`
	Provider         string `json:"provider"`
	PanelURL         string `json:"panel_url"`
	PanelDesc        string `json:"panel_desc"`
	SubscriptionURL  string `json:"subscription_url"`
	SubscriptionDesc string `json:"subscription_desc"`
	AssetsDir        string `json:"assets_dir"`
	ManifestPath     string `json:"manifest_path"`
	CheckPath        string `json:"check_path"`
	ConfigPath       string `json:"config_path"`
	FilesPath        string `json:"files_path"`
	ReadTimeoutSec   int    `json:"read_timeout_seconds"`
	WriteTimeoutSec  int    `json:"write_timeout_seconds"`
}

type manifest struct {
	Releases []release `json:"releases"`
}

type release struct {
	Version     string `json:"version"`
	Platform    string `json:"platform"`
	File        string `json:"file"`
	Notes       string `json:"notes"`
	Mandatory   bool   `json:"mandatory"`
	Direct      bool   `json:"direct"`
	Description string `json:"description"`
	Checksum    string `json:"checksum"`
	FileSize    int64  `json:"file_size"`
	PublishedAt string `json:"published_at"`
}

type checkResponse struct {
	LatestVersion   string `json:"latest_version"`
	UpdateAvailable bool   `json:"update_available"`
	DownloadURL     string `json:"download_url"`
	ReleaseNotes    string `json:"release_notes"`
	ForceUpdate     bool   `json:"force_update"`
}

type configJSON struct {
	Panels       map[string][]configEntry `json:"panels,omitempty"`
	Update       []updateEntry            `json:"update,omitempty"`
	Subscription *subscriptionSection     `json:"subscription,omitempty"`
}

type configEntry struct {
	URL         string `json:"url"`
	Description string `json:"description,omitempty"`
}

type updateEntry struct {
	URL            string `json:"url,omitempty"`
	DownloadURL    string `json:"downloadUrl,omitempty"`
	DownloadURLAlt string `json:"download_url,omitempty"`
	Description    string `json:"description,omitempty"`
	Platform       string `json:"platform,omitempty"`
	Version        string `json:"version,omitempty"`
	LatestVersion  string `json:"latestVersion,omitempty"`
	LatestVersion2 string `json:"latest_version,omitempty"`
	Notes          string `json:"notes,omitempty"`
	Mandatory      bool   `json:"mandatory,omitempty"`
	DirectDownload bool   `json:"directDownload,omitempty"`
	FileSize       int64  `json:"fileSize,omitempty"`
	Checksum       string `json:"checksum,omitempty"`
}

type subscriptionSection struct {
	URLs []configEntry `json:"urls,omitempty"`
}

type app struct {
	cfg      serverConfig
	manifest manifest
}

func main() {
	cfgPath := flag.String("config", "config.json", "path to update-pan config")
	flag.Parse()

	cfg, err := loadConfig(*cfgPath)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	manifestData, err := loadManifest(cfg.ManifestPath)
	if err != nil {
		log.Fatalf("load manifest: %v", err)
	}
	manifestData.Releases, err = computeFileMetadata(cfg.AssetsDir, manifestData.Releases)
	if err != nil {
		log.Fatalf("compute file metadata: %v", err)
	}

	application := &app{
		cfg:      cfg,
		manifest: manifestData,
	}

	mux := http.NewServeMux()
	mux.Handle(cfg.CheckPath, application.withLogging(http.HandlerFunc(application.handleCheckUpdate)))
	mux.Handle(cfg.ConfigPath, application.withLogging(http.HandlerFunc(application.handleConfigJSON)))
	mux.Handle(cfg.FilesPath, application.withLogging(http.StripPrefix(cfg.FilesPath, http.FileServer(http.Dir(cfg.AssetsDir)))))
	mux.Handle("/healthz", application.withLogging(http.HandlerFunc(handleHealth)))

	server := &http.Server{
		Addr:         cfg.ListenAddr,
		Handler:      mux,
		ReadTimeout:  cfg.ReadTimeout,
		WriteTimeout: cfg.WriteTimeout,
	}

	log.Printf("update-pan listening on %s", cfg.ListenAddr)
	log.Printf("check API: %s%s", cfg.PublicBaseURL, cfg.CheckPath)
	log.Printf("config.json: %s%s", cfg.PublicBaseURL, cfg.ConfigPath)
	log.Printf("file base: %s%s", cfg.PublicBaseURL, cfg.FilesPath)

	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("serve: %v", err)
	}
}

func loadConfig(path string) (serverConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return serverConfig{}, err
	}

	var raw rawConfig
	if err := json.Unmarshal(data, &raw); err != nil {
		return serverConfig{}, err
	}

	cfg := serverConfig{
		ListenAddr:       firstNonEmpty(raw.ListenAddr, ":8080"),
		PublicBaseURL:    strings.TrimRight(firstNonEmpty(raw.PublicBaseURL, "http://127.0.0.1:8080"), "/"),
		Provider:         firstNonEmpty(raw.Provider, "mihomo"),
		PanelURL:         strings.TrimSpace(raw.PanelURL),
		PanelDesc:        firstNonEmpty(raw.PanelDesc, "Main panel"),
		SubscriptionURL:  strings.TrimSpace(raw.SubscriptionURL),
		SubscriptionDesc: firstNonEmpty(raw.SubscriptionDesc, "Main subscription"),
		AssetsDir:        firstNonEmpty(raw.AssetsDir, "./data/files"),
		ManifestPath:     firstNonEmpty(raw.ManifestPath, "./data/releases.json"),
		CheckPath:        normalizeRoute(firstNonEmpty(raw.CheckPath, "/api/v1/check-update")),
		ConfigPath:       normalizeRoute(firstNonEmpty(raw.ConfigPath, "/config.json")),
		FilesPath:        normalizeRoute(firstNonEmpty(raw.FilesPath, "/files/")),
		ReadTimeout:      time.Duration(max(raw.ReadTimeoutSec, 10)) * time.Second,
		WriteTimeout:     time.Duration(max(raw.WriteTimeoutSec, 60)) * time.Second,
	}

	if !strings.HasSuffix(cfg.FilesPath, "/") {
		cfg.FilesPath += "/"
	}

	if cfg.PanelURL == "" {
		return serverConfig{}, errors.New("panel_url is required")
	}

	return cfg, nil
}

func loadManifest(path string) (manifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return manifest{}, err
	}

	var m manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return manifest{}, err
	}

	for i := range m.Releases {
		entry := &m.Releases[i]
		entry.Platform = strings.ToLower(strings.TrimSpace(entry.Platform))
		if entry.Version == "" || entry.Platform == "" || entry.File == "" {
			return manifest{}, fmt.Errorf("invalid release entry at index %d", i)
		}
	}

	return m, nil
}

func (a *app) handleCheckUpdate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	currentVersion := strings.TrimSpace(r.URL.Query().Get("version"))
	platform := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("platform")))
	if platform == "" {
		writeError(w, http.StatusBadRequest, "missing platform")
		return
	}

	entry, ok := a.latestReleaseForPlatform(platform)
	if !ok {
		writeError(w, http.StatusNotFound, "no release for platform")
		return
	}

	resp := checkResponse{
		LatestVersion:   entry.Version,
		UpdateAvailable: currentVersion == "" || compareVersion(entry.Version, currentVersion) > 0 || entry.Mandatory,
		DownloadURL:     a.fileURL(entry.File),
		ReleaseNotes:    entry.Notes,
		ForceUpdate:     entry.Mandatory,
	}
	writeJSON(w, http.StatusOK, resp)
}

func (a *app) handleConfigJSON(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	updateEntries := make([]updateEntry, 0, len(a.manifest.Releases))
	for _, rel := range sortedReleases(a.manifest.Releases) {
		url := a.fileURL(rel.File)
		updateEntries = append(updateEntries, updateEntry{
			URL:            fmt.Sprintf("%s%s", a.cfg.PublicBaseURL, a.cfg.CheckPath),
			DownloadURL:    url,
			DownloadURLAlt: url,
			Description:    firstNonEmpty(rel.Description, rel.Platform+" release"),
			Platform:       rel.Platform,
			Version:        rel.Version,
			LatestVersion:  rel.Version,
			LatestVersion2: rel.Version,
			Notes:          rel.Notes,
			Mandatory:      rel.Mandatory,
			DirectDownload: rel.Direct,
			FileSize:       rel.FileSize,
			Checksum:       rel.Checksum,
		})
	}

	resp := configJSON{
		Panels: map[string][]configEntry{
			a.cfg.Provider: {
				{
					URL:         a.cfg.PanelURL,
					Description: a.cfg.PanelDesc,
				},
			},
		},
		Update: updateEntries,
	}

	if a.cfg.SubscriptionURL != "" {
		resp.Subscription = &subscriptionSection{
			URLs: []configEntry{
				{
					URL:         a.cfg.SubscriptionURL,
					Description: a.cfg.SubscriptionDesc,
				},
			},
		}
	}

	writeJSON(w, http.StatusOK, resp)
}

func (a *app) latestReleaseForPlatform(platform string) (release, bool) {
	var candidates []release
	for _, rel := range a.manifest.Releases {
		if rel.Platform == platform {
			candidates = append(candidates, rel)
		}
	}
	if len(candidates) == 0 {
		return release{}, false
	}

	sort.Slice(candidates, func(i, j int) bool {
		return compareVersion(candidates[i].Version, candidates[j].Version) > 0
	})
	return candidates[0], true
}

func sortedReleases(releases []release) []release {
	cp := make([]release, len(releases))
	copy(cp, releases)
	sort.Slice(cp, func(i, j int) bool {
		if cp[i].Platform == cp[j].Platform {
			return compareVersion(cp[i].Version, cp[j].Version) > 0
		}
		return cp[i].Platform < cp[j].Platform
	})
	return cp
}

func (a *app) fileURL(name string) string {
	return fmt.Sprintf("%s%s%s", a.cfg.PublicBaseURL, a.cfg.FilesPath, strings.TrimLeft(name, "/"))
}

func (a *app) withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start).Round(time.Millisecond))
	})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	_ = encoder.Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func compareVersion(a, b string) int {
	as := parseVersionParts(a)
	bs := parseVersionParts(b)
	maxLen := len(as)
	if len(bs) > maxLen {
		maxLen = len(bs)
	}
	for i := 0; i < maxLen; i++ {
		av := 0
		if i < len(as) {
			av = as[i]
		}
		bv := 0
		if i < len(bs) {
			bv = bs[i]
		}
		if av > bv {
			return 1
		}
		if av < bv {
			return -1
		}
	}
	return 0
}

func parseVersionParts(v string) []int {
	cleaned := strings.TrimSpace(v)
	cleaned = strings.TrimPrefix(strings.ToLower(cleaned), "v")
	parts := strings.FieldsFunc(cleaned, func(r rune) bool {
		return r == '.' || r == '-' || r == '_' || r == '+'
	})
	out := make([]int, 0, len(parts))
	for _, part := range parts {
		n, err := strconv.Atoi(part)
		if err != nil {
			out = append(out, 0)
			continue
		}
		out = append(out, n)
	}
	return out
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

func normalizeRoute(route string) string {
	if route == "" {
		return "/"
	}
	if !strings.HasPrefix(route, "/") {
		route = "/" + route
	}
	return route
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func computeFileMetadata(root string, releases []release) ([]release, error) {
	out := make([]release, 0, len(releases))
	for _, rel := range releases {
		filePath := filepath.Join(root, filepath.FromSlash(rel.File))
		info, err := os.Stat(filePath)
		if err != nil {
			return nil, err
		}
		rel.FileSize = info.Size()
		if rel.Checksum == "" {
			sum, err := sha256File(filePath)
			if err != nil {
				return nil, err
			}
			rel.Checksum = sum
		}
		out = append(out, rel)
	}
	return out, nil
}

func sha256File(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()

	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}
