# *arr Stack Helm Chart

A complete media automation stack for managing and downloading movies, TV shows, music, books, and subtitles, with automated transcoding for Raspberry Pi compatibility.

## Overview

This Helm chart deploys the following applications:

| Application | Purpose | Port | URL |
|-------------|---------|------|-----|
| **Sonarr** | TV show management & automation | 8989 | sonarr.local.nunosousa.dev |
| **Radarr** | Movie management & automation | 7878 | radarr.local.nunosousa.dev |
| **Lidarr** | Music management & automation | 8686 | lidarr.local.nunosousa.dev |
| **Readarr** | Book/audiobook management | 8787 | readarr.local.nunosousa.dev |
| **Prowlarr** | Indexer management (central) | 9696 | prowlarr.local.nunosousa.dev |
| **Bazarr** | Subtitle management | 6767 | bazarr.local.nunosousa.dev |
| **qBittorrent** | Download client | 8080 | qbittorrent.local.nunosousa.dev |
| **Tdarr** | Automated transcoding | 8265 | tdarr.local.nunosousa.dev |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           User Request                              │
│                    "I want Movie X / Show Y"                        │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           Prowlarr                                  │
│              Central indexer manager for all *arr apps              │
│         Searches torrent/usenet indexers for content                │
└─────────────────────────────────────────────────────────────────────┘
                                    │
            ┌───────────────────────┼───────────────────────┐
            ▼                       ▼                       ▼
    ┌──────────────┐       ┌──────────────┐       ┌──────────────┐
    │    Sonarr    │       │    Radarr    │       │   Lidarr     │
    │  (TV Shows)  │       │   (Movies)   │       │   (Music)    │
    └──────────────┘       └──────────────┘       └──────────────┘
            │                       │                       │
            └───────────────────────┼───────────────────────┘
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         qBittorrent                                 │
│                    Downloads the content                            │
│              Saves to /media/downloads/{category}                   │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      NFS Media Volume                               │
│                   /media (shared mount)                             │
│  ┌─────────────┬─────────────┬─────────────┬─────────────┐          │
│  │  /movies    │    /tv      │   /music    │   /books    │          │
│  └─────────────┴─────────────┴─────────────┴─────────────┘          │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│            Tdarr                │  │          Jellyfin               │
│   Monitors & transcodes to      │  │   Media server - streams to     │
│   RPi-compatible formats        │  │   your devices                  │
│   (H.264/AAC)                   │  │                                 │
└─────────────────────────────────┘  └─────────────────────────────────┘
```

## Storage Layout

All applications share the same NFS volume mounted at `/media`:

```
/media/
├── downloads/          # qBittorrent downloads here
│   ├── movies/         # Category for movie downloads
│   ├── tv/             # Category for TV downloads
│   ├── music/          # Category for music downloads
│   └── books/          # Category for book downloads
├── movies/             # Radarr moves completed movies here
├── tv/                 # Sonarr moves completed TV shows here
├── music/              # Lidarr moves completed music here
└── books/              # Readarr moves completed books here
```

**Important:** All apps share the same volume, enabling **hardlinks** instead of copies. This means:
- Instant "moves" (no actual data copying)
- No duplicate disk space usage
- Seeding continues while media is organized

## Initial Setup Guide

### Step 1: Configure qBittorrent

1. Access qBittorrent at `https://qbittorrent.local.nunosousa.dev`
2. Default credentials: `admin` / `adminadmin` (change immediately!)
3. Go to **Settings → Downloads**:
   - Default Save Path: `/media/downloads`
   - Keep incomplete torrents in: `/media/downloads/incomplete`
4. Go to **Settings → Categories**, create:
   - `movies` → Save path: `/media/downloads/movies`
   - `tv` → Save path: `/media/downloads/tv`
   - `music` → Save path: `/media/downloads/music`
   - `books` → Save path: `/media/downloads/books`

### Step 2: Configure Prowlarr (Indexer Manager)

1. Access Prowlarr at `https://prowlarr.local.nunosousa.dev`
2. Complete initial setup (create username/password)
3. **Add Indexers**: Settings → Indexers → Add your torrent/usenet indexers
4. **Connect to *arr apps**: Settings → Apps → Add:

   | Application | Prowlarr Server | App Server | API Key |
   |-------------|-----------------|------------|---------|
   | Sonarr | `http://prowlarr.arr-stack.svc:9696` | `http://sonarr.arr-stack.svc:8989` | (from Sonarr) |
   | Radarr | `http://prowlarr.arr-stack.svc:9696` | `http://radarr.arr-stack.svc:7878` | (from Radarr) |
   | Lidarr | `http://prowlarr.arr-stack.svc:9696` | `http://lidarr.arr-stack.svc:8686` | (from Lidarr) |
   | Readarr | `http://prowlarr.arr-stack.svc:9696` | `http://readarr.arr-stack.svc:8787` | (from Readarr) |

### Step 3: Configure Sonarr (TV Shows)

1. Access Sonarr at `https://sonarr.local.nunosousa.dev`
2. Complete initial setup
3. **Add Download Client**: Settings → Download Clients → Add qBittorrent:
   - Host: `qbittorrent.arr-stack.svc`
   - Port: `8080`
   - Username/Password: (your qBittorrent credentials)
   - Category: `tv`
4. **Add Root Folder**: Settings → Media Management → Root Folders:
   - Path: `/media/tv`
5. **Get API Key**: Settings → General → API Key (needed for Prowlarr)

### Step 4: Configure Radarr (Movies)

1. Access Radarr at `https://radarr.local.nunosousa.dev`
2. Complete initial setup
3. **Add Download Client**: Settings → Download Clients → Add qBittorrent:
   - Host: `qbittorrent.arr-stack.svc`
   - Port: `8080`
   - Category: `movies`
4. **Add Root Folder**: Settings → Media Management → Root Folders:
   - Path: `/media/movies`

### Step 5: Configure Lidarr (Music)

1. Access Lidarr at `https://lidarr.local.nunosousa.dev`
2. Complete initial setup
3. **Add Download Client**: Settings → Download Clients → Add qBittorrent:
   - Host: `qbittorrent.arr-stack.svc`
   - Port: `8080`
   - Category: `music`
4. **Add Root Folder**: Settings → Media Management → Root Folders:
   - Path: `/media/music`

### Step 6: Configure Readarr (Books)

1. Access Readarr at `https://readarr.local.nunosousa.dev`
2. Complete initial setup
3. **Add Download Client**: Settings → Download Clients → Add qBittorrent:
   - Host: `qbittorrent.arr-stack.svc`
   - Port: `8080`
   - Category: `books`
4. **Add Root Folder**: Settings → Media Management → Root Folders:
   - Path: `/media/books`

### Step 7: Configure Bazarr (Subtitles)

1. Access Bazarr at `https://bazarr.local.nunosousa.dev`
2. **Connect to Sonarr**: Settings → Sonarr:
   - Address: `sonarr.arr-stack.svc`
   - Port: `8989`
   - API Key: (from Sonarr)
3. **Connect to Radarr**: Settings → Radarr:
   - Address: `radarr.arr-stack.svc`
   - Port: `7878`
   - API Key: (from Radarr)
4. **Add Subtitle Providers**: Settings → Providers (OpenSubtitles, etc.)

### Step 8: Configure Jellyfin

1. Access Jellyfin at `https://jellyfin.local.nunosousa.dev`
2. **Add Libraries**:
   - Movies → `/media/movies`
   - TV Shows → `/media/tv`
   - Music → `/media/music`
3. Enable automatic library scanning or set a schedule

## RPi Optimization: Quality Profiles & Transcoding

Since Raspberry Pi has limited transcoding power, this stack uses two strategies:

### Strategy 1: Quality Profiles (Download Compatible Formats)

Configure *arr apps to prefer RPi-compatible formats:

#### Radarr Quality Profile Setup

1. Go to **Settings → Profiles**
2. Edit or create a profile (e.g., "RPi Optimized")
3. **Quality Rankings** (drag to reorder, top = most preferred):
   ```
   1. WEBDL-1080p      ← Usually H.264, highly compatible
   2. WEBRip-1080p     ← Usually H.264
   3. HDTV-1080p       ← Usually H.264
   4. Bluray-1080p     ← Often HEVC, may need transcoding
   5. WEBDL-720p       ← Fallback, very compatible
   ```
4. **Custom Formats** (Settings → Custom Formats):
   - Create "H264" format: Condition → Release Title → `x264|h\.?264`
   - Create "HEVC" format: Condition → Release Title → `x265|h\.?265|hevc`
   - In profile, set H264 score: `+50`, HEVC score: `-25`

#### Sonarr Quality Profile Setup

Same approach as Radarr:
1. Prefer WEBDL/WEBRip over Bluray
2. Add custom formats to score H.264 higher than HEVC

### Strategy 2: Tdarr (Automated Transcoding)

Tdarr monitors your media library and automatically converts incompatible files.

#### Step 9: Configure Tdarr

1. Access Tdarr at `https://tdarr.local.nunosousa.dev`
2. **Initial Setup**:
   - Create admin account
   - The node "rpi-node" should auto-register

3. **Add Libraries** (Libraries tab):

   **Movies Library:**
   - Source: `/media/movies`
   - Transcode cache: `/temp`
   - Output: `/media/movies` (same as source for in-place conversion)
   - Enable: Scan on start, Watch folder

   **TV Library:**
   - Source: `/media/tv`
   - Transcode cache: `/temp`
   - Output: `/media/tv`
   - Enable: Scan on start, Watch folder

4. **Configure Transcode Plugin** (Plugins tab):

   For RPi compatibility, use this plugin flow:
   
   **Filter by codec (skip if already H.264):**
   - Plugin: `Tdarr_Plugin_MC93_Migz1FFMPEG_CPU`
   - Or use community plugin: `Tdarr_Plugin_00td_filter_by_codec`
   
   **Transcode to H.264/AAC:**
   - Plugin: `Tdarr_Plugin_MC93_Migz2CleanTitle`
   - Plugin: `Tdarr_Plugin_x1yz_FFMPEG_Transcode_Customizable`
     ```
     Video Codec: libx264
     Video CRF: 23 (good quality/size balance)
     Audio Codec: aac
     Audio Bitrate: 192k
     Container: mkv
     ```

5. **Node Configuration** (Nodes tab):
   - Click on "rpi-node"
   - Set Transcode GPU/CPU workers: `1` (RPi is limited)
   - Set Health Check CPU workers: `1`
   - Enable "Process" to start transcoding

6. **Recommended Plugin Stack:**
   ```
   1. Filter: Skip if already H.264
   2. Filter: Skip if resolution > 1080p
   3. Transcode: Convert to H.264/AAC
   4. Clean: Remove extra audio tracks (optional)
   5. Clean: Remove extra subtitle tracks (optional)
   ```

### RPi-Compatible Codecs Reference

| Codec | RPi 4 Support | Notes |
|-------|---------------|-------|
| H.264 | ✅ Hardware decode | Best compatibility |
| H.265/HEVC | ✅ Hardware decode | Good, but H.264 more universal |
| VP9 | ⚠️ Software only | Will need transcoding |
| AV1 | ❌ No support | Must convert |
| AAC | ✅ | Audio - universal |
| AC3/EAC3 | ✅ | Audio - universal |
| DTS | ⚠️ | May need passthrough |

### Tdarr Queue Priority

Files are processed in this order:
1. Recently added (newest first)
2. Smaller files first (faster processing)

**Tip:** Processing on RPi is slow. For large libraries, consider:
- Running Tdarr node on a more powerful machine
- Let it run overnight
- Prioritize new content only

## Adding New Media

### Adding a Movie

1. Go to **Radarr** → Movies → Add New
2. Search for the movie
3. Select quality profile and root folder (`/media/movies`)
4. Click "Add Movie"
5. Radarr will search indexers (via Prowlarr) and send to qBittorrent
6. Once downloaded, Radarr moves/hardlinks to `/media/movies`
7. Jellyfin picks it up on next scan

### Adding a TV Show

1. Go to **Sonarr** → Series → Add New
2. Search for the show
3. Select quality profile and root folder (`/media/tv`)
4. Choose which seasons/episodes to monitor
5. Click "Add Series"
6. Sonarr handles the rest automatically

### Adding Music

1. Go to **Lidarr** → Artist → Add New
2. Search for the artist
3. Select quality profile and root folder (`/media/music`)
4. Click "Add Artist"
5. Lidarr will download discography based on your settings

### Adding Books/Audiobooks

1. Go to **Readarr** → Author → Add New
2. Search for the author
3. Select quality profile and root folder (`/media/books`)
4. Click "Add Author"

## Internal Service Discovery

All apps communicate via Kubernetes DNS:

| Service | Internal URL |
|---------|--------------|
| Sonarr | `http://sonarr.arr-stack.svc:8989` |
| Radarr | `http://radarr.arr-stack.svc:7878` |
| Prowlarr | `http://prowlarr.arr-stack.svc:9696` |
| Lidarr | `http://lidarr.arr-stack.svc:8686` |
| Bazarr | `http://bazarr.arr-stack.svc:6767` |
| Readarr | `http://readarr.arr-stack.svc:8787` |
| qBittorrent | `http://qbittorrent.arr-stack.svc:8080` |
| Tdarr | `http://tdarr.arr-stack.svc:8265` |
| Tdarr Server | `http://tdarr.arr-stack.svc:8266` |

## Resource Requirements

| App | Memory Request | Memory Limit | Typical Usage |
|-----|---------------|--------------|---------------|
| Sonarr | 256Mi | 512Mi | ~200Mi idle |
| Radarr | 256Mi | 512Mi | ~200Mi idle |
| Prowlarr | 128Mi | 256Mi | ~100Mi idle |
| Lidarr | 256Mi | 512Mi | ~200Mi idle |
| Bazarr | 128Mi | 256Mi | ~100Mi idle |
| Readarr | 256Mi | 512Mi | ~200Mi idle |
| qBittorrent | 256Mi | 512Mi | ~150Mi idle |
| Tdarr Server | 256Mi | 512Mi | ~200Mi idle |
| Tdarr Node | 512Mi | 2Gi | ~1GB during transcode |
| **Total** | **2.2GB** | **5.5GB** | ~2GB typical |

Suitable for Raspberry Pi 4B (8GB) or similar.

## Troubleshooting

### "No available server" error
- Check if pods are ready: `kubectl get pods -n arr-stack`
- Pods showing `0/1` means readiness probe is failing
- Check logs: `kubectl logs -n arr-stack <pod-name>`

### Volume attachment errors
- iSCSI volumes are ReadWriteOnce (single pod only)
- Delete stuck pods: `kubectl delete pod -n arr-stack <old-pod> --force`
- Deployments use `Recreate` strategy to prevent this

### Apps can't connect to each other
- Use internal DNS names (e.g., `sonarr.arr-stack.svc`)
- Don't use external URLs for internal communication
- Check if services exist: `kubectl get svc -n arr-stack`

### Downloads not being imported
- Ensure qBittorrent categories match *arr app settings
- Check permissions (PUID/PGID should be 1000)
- Verify paths match between apps

## Configuration Values

See `values.yaml` for all configurable options:

```yaml
hostnames:
  sonarr: sonarr.local.nunosousa.dev
  radarr: radarr.local.nunosousa.dev
  # ... etc

sonarr:
  image: linuxserver/sonarr:4.0.14
  resources:
    requests:
      memory: "256Mi"
    limits:
      memory: "512Mi"
  config:
    storageClassName: truenas-iscsi-retain
    size: 5Gi

media:
  nfsServer: 10.0.0.3
  nfsPath: /mnt/data/media
  size: 500Gi
```

## Useful Commands

```bash
# Check all pods
kubectl get pods -n arr-stack

# Check pod logs
kubectl logs -n arr-stack -l app=sonarr -f

# Check resource usage
kubectl top pods -n arr-stack

# Restart a deployment
kubectl rollout restart deployment -n arr-stack sonarr

# Force sync with ArgoCD
argocd app sync arr-stack
```
