PLUGIN_NAME  := @tarquinen/opencode-dcp
BUNDLE_DIR   := $(CURDIR)/dist-bundle
BUNDLE_ENTRY := $(BUNDLE_DIR)/index.js
CONFIG_HOME  := $(HOME)/.config/opencode
CACHE_DIR    := $(HOME)/.cache/opencode
CONFIG_FILE  := $(CONFIG_HOME)/opencode.json
INSTALL_DIR  := $(CONFIG_HOME)/plugins/dcp
INSTALL_ENTRY := $(INSTALL_DIR)/index.js
VERSION      := $(shell node -p "require('./package.json').version" 2>/dev/null || echo "0.0.0")

.PHONY: bundle dist prepare configure install reinstall uninstall clean status

# File target: only rebuilds when sources change.
# Guarded so the rule does not exist in tarball-only contexts (no index.ts).
ifneq ($(wildcard index.ts),)
$(BUNDLE_ENTRY): index.ts $(wildcard lib/**/*.ts scripts/bundle.ts)
	@echo "Building self-contained bundle..."
	bun run scripts/bundle.ts
endif

bundle: $(BUNDLE_ENTRY)

dist: $(BUNDLE_ENTRY)
	@ARCHIVE="opencode-dcp-$(VERSION).tar.gz"; \
	STAGING=$$(mktemp -d); \
	mkdir -p "$$STAGING/opencode-dcp-$(VERSION)/dist-bundle"; \
	cp Makefile "$$STAGING/opencode-dcp-$(VERSION)/"; \
	cp "$(BUNDLE_DIR)/index.js" "$(BUNDLE_DIR)/tiktoken_bg.wasm" "$$STAGING/opencode-dcp-$(VERSION)/dist-bundle/"; \
	tar -czf "$$ARCHIVE" -C "$$STAGING" "opencode-dcp-$(VERSION)"; \
	rm -rf "$$STAGING"; \
	echo "Created $$ARCHIVE"; \
	echo "Usage: tar -xzf $$ARCHIVE && cd opencode-dcp-$(VERSION) && make install"

# Removes stale DCP installations (npm package, old file:// paths) without
# touching the current install entry or any other user settings.
prepare:
	@echo "Preparing: removing stale DCP installations..."
	@if [ -f "$(CONFIG_FILE)" ]; then \
		node -e " \
			const fs = require('fs'); \
			const cfg = JSON.parse(fs.readFileSync('$(CONFIG_FILE)', 'utf8')); \
			if (!cfg.plugin) { process.exit(0); } \
			const currentEntry = 'file://$(INSTALL_ENTRY)'; \
			const before = cfg.plugin.length; \
			const filtered = cfg.plugin.filter(p => { \
				if (p === currentEntry) return true; \
				if (p === '$(PLUGIN_NAME)') return false; \
				if (p.startsWith('file://') && (p.includes('opencode-dcp') || p.includes('dist-bundle'))) return false; \
				return true; \
			}); \
			const removed = before - filtered.length; \
			if (filtered.length === 0) delete cfg.plugin; \
			else cfg.plugin = filtered; \
			fs.writeFileSync('$(CONFIG_FILE)', JSON.stringify(cfg, null, 4) + '\n'); \
			if (removed > 0) console.log('Removed ' + removed + ' stale DCP entry/entries from $(CONFIG_FILE)'); \
			else console.log('No stale DCP entries in $(CONFIG_FILE)'); \
		"; \
	fi
	@if [ -f "$(CACHE_DIR)/package.json" ]; then \
		node -e " \
			const fs = require('fs'); \
			const cfg = JSON.parse(fs.readFileSync('$(CACHE_DIR)/package.json', 'utf8')); \
			if (cfg.dependencies && cfg.dependencies['$(PLUGIN_NAME)']) { \
				delete cfg.dependencies['$(PLUGIN_NAME)']; \
				fs.writeFileSync('$(CACHE_DIR)/package.json', JSON.stringify(cfg, null, 4) + '\n'); \
				console.log('Removed $(PLUGIN_NAME) from $(CACHE_DIR)/package.json'); \
			} else { \
				console.log('No cached npm entry found in $(CACHE_DIR)/package.json'); \
			} \
		"; \
	fi
	@if [ -d "$(CACHE_DIR)/node_modules/$(PLUGIN_NAME)" ]; then \
		rm -rf "$(CACHE_DIR)/node_modules/$(PLUGIN_NAME)"; \
		echo "Removed $(CACHE_DIR)/node_modules/$(PLUGIN_NAME)"; \
	fi
	@echo "Prepare complete."

configure:
	@if [ ! -f "$(INSTALL_ENTRY)" ]; then \
		echo "Error: plugin not installed at $(INSTALL_ENTRY). Run 'make install' first."; \
		exit 1; \
	fi
	@echo "Configuring opencode to use plugin at $(INSTALL_ENTRY)..."
	@if [ ! -f "$(CONFIG_FILE)" ]; then \
		mkdir -p "$(CONFIG_HOME)"; \
		printf '{\n    "plugin": [\n        "file://$(INSTALL_ENTRY)"\n    ]\n}\n' > "$(CONFIG_FILE)"; \
		echo "Created $(CONFIG_FILE) with plugin entry."; \
	else \
		node -e " \
			const fs = require('fs'); \
			const cfg = JSON.parse(fs.readFileSync('$(CONFIG_FILE)', 'utf8')); \
			cfg.plugin = cfg.plugin || []; \
			if (!cfg.plugin.includes('file://$(INSTALL_ENTRY)')) { \
				cfg.plugin.push('file://$(INSTALL_ENTRY)'); \
				fs.writeFileSync('$(CONFIG_FILE)', JSON.stringify(cfg, null, 4) + '\n'); \
				console.log('Added plugin entry to $(CONFIG_FILE)'); \
			} else { \
				console.log('Plugin entry already present in $(CONFIG_FILE)'); \
			} \
		"; \
	fi
	@echo "Done. Restart opencode to load the plugin."

install: $(BUNDLE_ENTRY) prepare
	@echo "Installing plugin to $(INSTALL_DIR)..."
	@mkdir -p "$(INSTALL_DIR)"
	@cp "$(BUNDLE_DIR)/index.js" "$(BUNDLE_DIR)/tiktoken_bg.wasm" "$(INSTALL_DIR)/"
	@echo "Installed to $(INSTALL_DIR)"
	@$(MAKE) --no-print-directory configure

reinstall: install

uninstall:
	@echo "Removing all DCP installations..."
	@if [ -f "$(CONFIG_FILE)" ]; then \
		node -e " \
			const fs = require('fs'); \
			const cfg = JSON.parse(fs.readFileSync('$(CONFIG_FILE)', 'utf8')); \
			if (!cfg.plugin) { process.exit(0); } \
			const before = cfg.plugin.length; \
			const filtered = cfg.plugin.filter(p => \
				p !== '$(PLUGIN_NAME)' && \
				!(p.startsWith('file://') && (p.includes('opencode-dcp') || p.includes('dist-bundle') || p.includes('plugins/dcp'))) \
			); \
			const removed = before - filtered.length; \
			if (filtered.length === 0) delete cfg.plugin; \
			else cfg.plugin = filtered; \
			fs.writeFileSync('$(CONFIG_FILE)', JSON.stringify(cfg, null, 4) + '\n'); \
			if (removed > 0) console.log('Removed ' + removed + ' DCP entry/entries from $(CONFIG_FILE)'); \
			else console.log('No DCP entries in $(CONFIG_FILE)'); \
		"; \
	fi
	@if [ -f "$(CACHE_DIR)/package.json" ]; then \
		node -e " \
			const fs = require('fs'); \
			const cfg = JSON.parse(fs.readFileSync('$(CACHE_DIR)/package.json', 'utf8')); \
			if (cfg.dependencies && cfg.dependencies['$(PLUGIN_NAME)']) { \
				delete cfg.dependencies['$(PLUGIN_NAME)']; \
				fs.writeFileSync('$(CACHE_DIR)/package.json', JSON.stringify(cfg, null, 4) + '\n'); \
				console.log('Removed $(PLUGIN_NAME) from $(CACHE_DIR)/package.json'); \
			} \
		"; \
	fi
	@if [ -d "$(CACHE_DIR)/node_modules/$(PLUGIN_NAME)" ]; then \
		rm -rf "$(CACHE_DIR)/node_modules/$(PLUGIN_NAME)"; \
		echo "Removed $(CACHE_DIR)/node_modules/$(PLUGIN_NAME)"; \
	fi
	@if [ -d "$(INSTALL_DIR)" ]; then \
		rm -rf "$(INSTALL_DIR)"; \
		echo "Removed $(INSTALL_DIR)"; \
	fi
	@echo "Uninstall complete. Restart opencode to apply."

clean:
	@rm -rf "$(BUNDLE_DIR)"
	@rm -f opencode-dcp-*.tar.gz
	@echo "Cleaned build output."

status:
	@echo "Plugin:   $(PLUGIN_NAME)"
	@echo "Source:   $(CURDIR)"
	@echo "Bundle:   $(BUNDLE_ENTRY)"
	@echo "Installed: $(INSTALL_DIR)"
	@echo ""
	@echo "Build:"
	@test -f "$(BUNDLE_ENTRY)" \
		&& echo "  $(BUNDLE_ENTRY) exists" \
		|| echo "  Not built (run 'make bundle')"
	@echo ""
	@echo "Install:"
	@test -f "$(INSTALL_ENTRY)" \
		&& echo "  $(INSTALL_ENTRY) exists" \
		|| echo "  Not installed (run 'make install')"
	@echo ""
	@echo "Config:   $(CONFIG_FILE)"
	@if [ -f "$(CONFIG_FILE)" ]; then \
		grep -q '"file://$(INSTALL_ENTRY)"' "$(CONFIG_FILE)" 2>/dev/null \
			&& echo "  Plugin registered" \
			|| (grep -q '"$(PLUGIN_NAME)"' "$(CONFIG_FILE)" 2>/dev/null \
				&& echo "  npm package registered (not bundle -- run 'make install')" \
				|| echo "  Plugin NOT registered (run 'make install')"); \
	else \
		echo "  No config found at $(CONFIG_FILE)"; \
	fi
	@echo ""
	@echo "Cache:    $(CACHE_DIR)"
	@test -d "$(CACHE_DIR)/node_modules/$(PLUGIN_NAME)" \
		&& echo "  Stale npm cache present (will be removed on next 'make install')" \
		|| echo "  No stale npm cache"
	@echo ""
	@echo "DCP config:"
	@test -f "$(CONFIG_HOME)/dcp.jsonc" \
		&& echo "  $(CONFIG_HOME)/dcp.jsonc" \
		|| (test -f "$(CONFIG_HOME)/dcp.json" \
			&& echo "  $(CONFIG_HOME)/dcp.json" \
			|| echo "  None (defaults will be used)")
