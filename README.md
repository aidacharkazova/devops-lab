# uni-devops-lab

Universitet tələbə portalı (Flask + Redis) üçün DevOps layihəsi. Kod Git-də branch və Merge Request-lərlə idarə olunur, portal Docker image-ə paketlənir, Compose ilə Redis-lə birlikdə işləyir və Ansible ilə app server-ə avtomatik qurulur. App server-də əl ilə heç nə quraşdırılmır.

| Endpoint   | Cavab                                       |
|------------|---------------------------------------------|
| `/`        | `University Student Portal is running`      |
| `/health`  | `{"status": "healthy"}`                     |
| `/visits`  | `{"visits": N}` — sayğac Redis-də saxlanılır |

## Struktur

```
uni-devops-lab/
├── app/
│   ├── app.py                    # Flask tətbiqi (dəyişdirilməyib)
│   └── requirements.txt          # flask==3.0.3, redis==5.0.7
├── Dockerfile                    # python:3.12-slim; əvvəl asılılıqlar, sonra kod
├── .dockerignore
├── compose.yml                   # portal + redis, named volume: redis-data
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.ini             # app server və SSH açarının yolu
│   ├── group_vars/app_servers.yml  # port, image adı, qovluq yolu
│   ├── templates/portal.env.j2   # Compose üçün .env (dəyişənlərdən yaranır)
│   ├── requirements.yml          # community.docker kolleksiyası
│   └── playbook.yml
├── test-server/                  # lokal test üçün Ubuntu 24.04 app server (SSH + systemd)
└── README.md
```

## Mərhələ 1 — Git

- Hər mərhələ ayrıca branch-də görülüb və Merge Request ilə `main`-ə birləşdirilib:
  `feature/git-setup` → `feature/docker` → `feature/ansible` → `docs/readme`.
- `main`-də birbaşa commit yoxdur (ilkin README commit-i istisna olmaqla).
- `.gitignore` faylı `.env`, `*.log` və private key fayllarını (`*.pem`, `*.key`, `id_*`) repository-yə buraxmır. Repository-də parol, token və ya private key yoxdur; inventory-də yalnız açar faylının **yolu** var.

## Mərhələ 2 — Docker

```bash
# Image-i yaratmaq və tək yoxlamaq
docker build -t student-portal:1.0 .
docker run --rm -p 8080:5000 student-portal:1.0      # http://localhost:8080

# Portal + Redis birlikdə
docker compose up -d --build
curl localhost:8080/visits
docker compose restart                               # sayğac sıfırlanmır
docker compose down && docker compose up -d          # konteynerlər silinsə də sayğac qalır
```

- Dockerfile-da `requirements.txt` koddan əvvəl kopyalanır, ona görə kod dəyişəndə asılılıqlar layer-i cache-dən götürülür. Konteyner root olmayan istifadəçi ilə işləyir.
- Portal Redis-ə servis adı ilə qoşulur: `REDIS_HOST=redis`.
- Redis `--appendonly yes` ilə işləyir, data `redis-data` named volume-da saxlanılır.
- Port və image adı `compose.yml`-də `${PORTAL_PORT:-8080}` və `${PORTAL_IMAGE:-student-portal:1.0}` kimi yazılıb. Lokal işləyəndə default dəyərlər, serverdə Ansible-ın yaratdığı `.env` faylı istifadə olunur.

## Mərhələ 3 — Ansible

### App server

Lokal testdə app server kimi `test-server/` istifadə olundu: Ubuntu 24.04 konteyneri. Orada yalnız systemd, OpenSSH, sudo və Python var (təzə cloud VM kimi). Docker yoxdur, onu playbook quraşdırır. Real VM üçün sadəcə `ansible/inventory.ini`-də `ansible_host` və `ansible_user` dəyişdirilir.

### Şifrəsiz SSH

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/uni_devops_lab

# Real VM:
ssh-copy-id -i ~/.ssh/uni_devops_lab.pub ubuntu@<server-ip>

# Lokal test server (public key image-ə yazılır, parolla giriş bağlıdır):
SSH_PUBKEY="$(cat ~/.ssh/uni_devops_lab.pub)" docker compose -f test-server/compose.yml up -d --build
ssh -i ~/.ssh/uni_devops_lab -p 2222 ubuntu@127.0.0.1
```

### Playbook-u işə salmaq

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible app_servers -m ping
ansible-playbook playbook.yml
```

Playbook nə edir:

1. Docker-in rəsmi apt repository-sini (GPG açarı + deb822 repo) əlavə edir.
2. `docker-ce` və Compose plugin-i quraşdırır, `docker` servisini aktiv edir (`enabled` + `started`).
3. `Dockerfile`, `.dockerignore`, `compose.yml` və `app/` fayllarını serverə köçürür.
4. Dəyişənlərdən `.env` faylı yaradır (`PORTAL_IMAGE`, `PORTAL_PORT`).
5. `docker_compose_v2` ilə image-i build edir və servisləri qaldırır. Image yalnız fayllar dəyişəndə yenidən build olunur.
6. Portalın `/health` cavabını yoxlayır və nəticəni ekrana çıxarır.

Dəyişənlər `ansible/group_vars/app_servers.yml`-dədir, playbook-da hard-code edilməyib:

| Dəyişən              | Dəyər                 |
|----------------------|-----------------------|
| `portal_image`       | `student-portal:1.0`  |
| `portal_port`        | `8080`                |
| `portal_project_dir` | `/opt/student-portal` |
| `portal_health_path` | `/health`             |

## Nəticələr

| Yoxlama   | Nəticə |
|-----------|--------|
| Playbook 1-ci icra | `ok=13 changed=9 failed=0` |
| Playbook 2-ci icra | `ok=13 changed=0 failed=0`: lazımsız dəyişiklik yoxdur |
| Health    | `/health -> HTTP 200 {'status': 'healthy'}` |
| Portal    | `http://<server-ip>:8080` açılır |
| Data      | `/visits`: 3 → servis restart-ından sonra 4 → server reboot-undan sonra 5 |

## Qarşılaşdığım problem

Docker repository-sini əvvəlcə `ansible.builtin.apt_repository` modulu ilə əlavə edirdim. ansible-core 2.21-də bu modul deprecation xəbərdarlığı verdi (2.25-də silinəcək) və tövsiyə olunan `deb822_repository`-yə keçdim. Yeni modulun iki fərqi var. Birincisi, serverdə `python3-debian` paketi lazımdır. İkincisi, o, apt cache-i özü yeniləmir, yəni repo əlavə olunandan dərhal sonra `docker-ce` paketi tapılmır. Cache-i hər icrada yeniləmək isə playbook-u lazımsız yavaşladardı.

Həll belə oldu: `python3-debian` ilk apt tapşırığına əlavə olundu. Repo tapşırığının nəticəsi `register: docker_repo` ilə saxlanılır və Docker paketlərini quraşdıran tapşırıqda `update_cache: "{{ docker_repo is changed }}"` yazılıb. Beləliklə cache yalnız repo ilk dəfə əlavə olunanda yenilənir, ikinci icrada isə heç bir tapşırıq dəyişiklik etmir (`changed=0`).
