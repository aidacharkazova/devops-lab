# uni-devops-lab

A DevOps project for the university student portal (Flask + Redis). The code lives in Git and every change reaches `main` through a branch and a pull request. The portal is packaged as a Docker image and runs together with Redis through Docker Compose. Ansible deploys it to the app server automatically, so nothing is installed on the app server by hand.

| Endpoint   | Response                                    |
|------------|---------------------------------------------|
| `/`        | `University Student Portal is running`      |
| `/health`  | `{"status": "healthy"}`                     |
| `/visits`  | `{"visits": N}`, a counter stored in Redis  |

## Structure

```
uni-devops-lab/
├── app/
│   ├── app.py                    # Flask application (unchanged)
│   └── requirements.txt          # flask==3.0.3, redis==5.0.7
├── Dockerfile                    # python:3.12-slim; dependencies first, then code
├── .dockerignore
├── compose.yml                   # portal + redis, named volume: redis-data
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.ini             # app server and path to the SSH key
│   ├── group_vars/app_servers.yml  # port, image name, directory path
│   ├── templates/portal.env.j2   # .env for Compose, generated from variables
│   ├── requirements.yml          # community.docker collection
│   └── playbook.yml
├── test-server/                  # Ubuntu 24.04 app server for local testing (SSH + systemd)
└── README.md
```

## Stage 1: Git

- Each stage was done on its own branch and merged into `main` through a pull request:
  `feature/git-setup` → `feature/docker` → `feature/ansible` → `docs/readme`.
- Apart from the initial README commit, nothing was committed directly to `main`.
- `.gitignore` keeps `.env`, `*.log` and private key files (`*.pem`, `*.key`, `id_*`) out of the repository. The repository has no passwords, tokens or private keys. The inventory only holds the **path** to the key file.

## Stage 2: Docker

```bash
# Build the image and test it on its own
docker build -t student-portal:1.0 .
docker run --rm -p 8080:5000 student-portal:1.0      # http://localhost:8080

# Portal + Redis together
docker compose up -d --build
curl localhost:8080/visits
docker compose restart                               # the counter is not reset
docker compose down && docker compose up -d          # the counter survives even when the containers are removed
```

- The Dockerfile copies `requirements.txt` before the code. When only the code changes, the dependency layer comes from the cache. The container runs as a non-root user.
- The portal connects to Redis by its service name: `REDIS_HOST=redis`.
- Redis runs with `--appendonly yes`, and its data is stored in the `redis-data` named volume.
- `compose.yml` reads the port and image name as `${PORTAL_PORT:-8080}` and `${PORTAL_IMAGE:-student-portal:1.0}`. Locally the default values are used; on the server they come from the `.env` file that Ansible creates.

## Stage 3: Ansible

### App server

For local testing, `test-server/` acts as the app server. It's an Ubuntu 24.04 container with only systemd, OpenSSH, sudo and Python, like a fresh cloud VM. It has no Docker; the playbook installs it. For a real VM, only `ansible_host` and `ansible_user` in `ansible/inventory.ini` need to change.

### Passwordless SSH

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/uni_devops_lab

# Real VM:
ssh-copy-id -i ~/.ssh/uni_devops_lab.pub ubuntu@<server-ip>

# Local test server (the public key is built into the image, password login is disabled):
SSH_PUBKEY="$(cat ~/.ssh/uni_devops_lab.pub)" docker compose -f test-server/compose.yml up -d --build
ssh -i ~/.ssh/uni_devops_lab -p 2222 ubuntu@127.0.0.1
```

### Running the playbook

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible app_servers -m ping
ansible-playbook playbook.yml
```

What the playbook does:

1. Adds Docker's official apt repository (GPG key + deb822 repo).
2. Installs `docker-ce` and the Compose plugin, and enables the `docker` service (`enabled` + `started`).
3. Copies `Dockerfile`, `.dockerignore`, `compose.yml` and `app/` to the server.
4. Creates a `.env` file from the variables (`PORTAL_IMAGE`, `PORTAL_PORT`).
5. Builds the image and starts the services with `docker_compose_v2`. The image is rebuilt only when the files change.
6. Checks the portal's `/health` response and prints the result.

The variables live in `ansible/group_vars/app_servers.yml` and are not hard-coded in the playbook:

| Variable             | Value                 |
|----------------------|-----------------------|
| `portal_image`       | `student-portal:1.0`  |
| `portal_port`        | `8080`                |
| `portal_project_dir` | `/opt/student-portal` |
| `portal_health_path` | `/health`             |

## Results

| Check     | Result |
|-----------|--------|
| Playbook, 1st run | `ok=13 changed=9 failed=0` |
| Playbook, 2nd run | `ok=13 changed=0 failed=0`: no unnecessary changes |
| Health    | `/health -> HTTP 200 {'status': 'healthy'}` |
| Portal    | opens at `http://<server-ip>:8080` |
| Data      | `/visits`: 3 → 4 after a service restart → 5 after a server reboot |

## A problem I ran into

At first I added the Docker repository with the `ansible.builtin.apt_repository` module. In ansible-core 2.21 this module printed a deprecation warning (it will be removed in 2.25), so I switched to the recommended `deb822_repository`. The new module behaves differently in two ways. First, it needs the `python3-debian` package on the server. Second, it doesn't refresh the apt cache by itself, so right after the repo is added, the `docker-ce` package can't be found. Refreshing the cache on every run would fix that, but it would slow the playbook down for no reason.

The fix: I added `python3-debian` to the first apt task. The repo task saves its result with `register: docker_repo`, and the task that installs the Docker packages uses `update_cache: "{{ docker_repo is changed }}"`. This way the cache is refreshed only when the repo is added for the first time, and on the second run no task changes anything (`changed=0`).
