LISTS_JSON := data/lists.json

.PHONY: all lists deps fetch fetch-all parse css build dev test clean help

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
	  | awk -F':.*##' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

all: build ## Materialize, fetch, parse, and build the site

deps: node_modules ## Install root pipeline dependencies (markdown-it)
node_modules: package.json
	npm install

lists: $(LISTS_JSON) ## Materialize lists.js -> data/lists.json
$(LISTS_JSON): lists.js
	@mkdir -p data
	node -e 'console.log(JSON.stringify(require("./lists.js"), null, 2))' > $@

# Two-stage fetch: stage 1 materializes lists.json so we can compute the
# RAW file list; stage 2 (recursive make) consumes it.
fetch: $(LISTS_JSON) ## Download raw markdown for every list
	@$(MAKE) --no-print-directory fetch-all

fetch-all: $(shell jq -r '.[].id' $(LISTS_JSON) 2>/dev/null | sed 's|^|data/raw/|; s|$$|.md|')

data/raw/%.md: $(LISTS_JSON)
	@mkdir -p data/raw
	$(eval REPO := $(shell jq -r --arg id $* '.[]|select(.id==$$id).repo' $(LISTS_JSON)))
	@echo "  fetching $(REPO)"
	@curl -fsSL "https://raw.githubusercontent.com/$(REPO)/HEAD/readme.md" -o $@ 2>/dev/null \
	  || curl -fsSL "https://raw.githubusercontent.com/$(REPO)/HEAD/README.md" -o $@

parse: deps fetch ## Parse markdown -> entries.json
	node scripts/parse_awesome.js $(LISTS_JSON) data/raw data/entries.json
	@mkdir -p webapp/static
	@cp data/entries.json webapp/static/entries.json

webapp/node_modules: webapp/package.json
	cd webapp && npm install

css: webapp/static/main.css ## Build Tailwind CSS bundle
webapp/static/main.css: webapp/src/main.css webapp/src/Pages/Home_.elm webapp/node_modules
	cd webapp && npx @tailwindcss/cli -i src/main.css -o static/main.css --minify

build: parse css ## Build production site to webapp/dist
	cd webapp && npx elm-land build

dev: parse css ## Run dev server with hot reload
	cd webapp && npx elm-land server

test: deps ## Run parser tests
	node --test scripts/*.test.js

clean: ## Remove build artifacts and dependencies
	rm -rf data/raw data/lists.json data/entries.json node_modules \
	       webapp/dist webapp/static/entries.json webapp/elm-stuff webapp/node_modules
