# Python env is managed by devenv — run targets inside `devenv shell` or with direnv active

.PHONY: help install install-client dev server client build preview clean

# ── Help ────────────────────────────────────────────────────────────────────

help:
	@printf '\n\033[1mTogether — available targets\033[0m\n\n'
	@printf '  \033[36minstall\033[0m          Install client dependencies (Python managed by devenv)\n'
	@printf '  \033[36minstall-client\033[0m   npm install for the client\n'
	@printf '\n'
	@printf '  \033[36mdev\033[0m              Run server and client in parallel\n'
	@printf '  \033[36mserver\033[0m           Start FastAPI server on :8000\n'
	@printf '  \033[36mclient\033[0m           Start Vite dev server on :5173\n'
	@printf '\n'
	@printf '  \033[36mbuild\033[0m            Build client for production\n'
	@printf '  \033[36mpreview\033[0m          Preview the production build\n'
	@printf '\n'
	@printf '  \033[36mclean\033[0m            Remove node_modules, dist, caches\n\n'

# ── Install ──────────────────────────────────────────────────────────────────

install-client:
	npm --prefix client install

install: install-client

# ── Run ──────────────────────────────────────────────────────────────────────

server:
	cd server && uvicorn main:app --reload --host 0.0.0.0 --port 8000

client:
	npm --prefix client run dev

dev: install
	$(MAKE) -j2 server client

# ── Build ────────────────────────────────────────────────────────────────────

build:
	npm --prefix client run build

preview: build
	npm --prefix client run preview

# ── Clean ────────────────────────────────────────────────────────────────────

clean:
	rm -rf client/node_modules client/dist
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type d -name .pytest_cache -exec rm -rf {} +
