BIN ?= ./.build/release/TrainerCLI

RUN_TS := $(or $(RUN_TS),$(shell date +%Y%m%d-%H%M%S))
RUN_ROOT ?= TrainingRuns/$(RUN_TS)
MERGED_DIR ?= $(RUN_ROOT)/merged
MODEL_PATH ?= Models/model-$(RUN_TS).json
BEST_MODEL ?= Models/model-best.json
EVAL_REPORT ?= Reports/eval-$(RUN_TS).json
EXPORT_DIR ?= Exports/export-$(RUN_TS)

SELFPLAY_SHARDS ?= 2
SELFPLAY_GAMES_PER_SHARD ?= 10000
SELFPLAY_PLAYERS ?= 4
SELFPLAY_SIMULATIONS ?= 256
SELFPLAY_MAX_CANDIDATES ?= 40
SELFPLAY_MAX_TURNS ?= 320
SELFPLAY_PARALLEL_PER_SHARD ?= 5
SELFPLAY_SEED_BASE ?= $(shell echo $(RUN_TS) | tr -d '-' | tail -c 10)
SELFPLAY_TEMPERATURE_DROP ?= 20

TRAIN_LIMIT ?= 2000000
TRAIN_LABEL ?= m4-$(RUN_TS)
TRAIN_POLICY_BLEND ?= 0.65
TRAIN_VALUE_BLEND ?= 0.70
TRAIN_SELECTED_BOOST ?= 1.2
TRAIN_MAX_ACTION_BIASES ?= 60000
TRAIN_RIDGE ?= 0.001
TRAIN_ARCHITECTURE ?= mlp
TRAIN_POLICY_ARCH ?= mlp
TRAIN_EPOCHS ?= 20
TRAIN_LR ?= 0.001
TRAIN_BATCH_SIZE ?= 256
TRAIN_AUGMENT ?= true
TRAIN_CUMULATIVE_WINDOW ?= 3

EVAL_GAMES ?= 3000
EVAL_PLAYERS ?= 4
EVAL_SIMULATIONS ?= 160
EVAL_MAX_CANDIDATES ?= 48
EVAL_MAX_TURNS ?= 320
EVAL_PARALLEL ?= 10
EVAL_SEED ?= 42

LOOP_COUNT ?= 5
PROMOTE_THRESHOLD ?= 0.55

.PHONY: help format build-trainer prepare m4-selfplay m4-selfplay-weekly m4-merge m4-train m4-eval m4-export m4-promote m4-all m4-loop m4-merge-cumulative

help:
	@echo "Usage:"
	@echo "  make build-trainer"
	@echo "  make m4-selfplay"
	@echo "  make m4-merge"
	@echo "  make m4-train"
	@echo "  make m4-eval"
	@echo "  make m4-export"
	@echo "  make m4-all"
	@echo "  make m4-loop              # $(LOOP_COUNT) cycles with auto-promote (threshold=$(PROMOTE_THRESHOLD))"
	@echo "  make m4-loop LOOP_COUNT=10"
	@echo ""
	@echo "Main output vars:"
	@echo "  RUN_ROOT=$(RUN_ROOT)"
	@echo "  MODEL_PATH=$(MODEL_PATH)"
	@echo "  EVAL_REPORT=$(EVAL_REPORT)"
	@echo "  EXPORT_DIR=$(EXPORT_DIR)"

format:
	@swift format swift-format format . -r -i

build-trainer:
	@swift build -c release --product TrainerCLI

prepare: build-trainer
	@mkdir -p "$(RUN_ROOT)" Models Reports Exports

m4-selfplay: prepare
	@echo "selfplay start: RUN_ROOT=$(RUN_ROOT)"
	@model_flag=""; \
	if [ -f "$(BEST_MODEL)" ]; then \
		model_flag="--model $(BEST_MODEL)"; \
		echo "  model: $(BEST_MODEL)"; \
	else \
		echo "  model: heuristic (no best model yet)"; \
	fi; \
	end=$$(( $(SELFPLAY_SHARDS) - 1 )); \
	for i in $$(seq 0 $$end); do \
		seed=$$(( $(SELFPLAY_SEED_BASE) + $$i )); \
		out="$(RUN_ROOT)/shard-$$i"; \
		log="$(RUN_ROOT)/shard-$$i.log"; \
		mkdir -p "$$out"; \
		echo "  shard $$i -> $$out (seed=$$seed)"; \
		( $(BIN) selfplay \
			--games $(SELFPLAY_GAMES_PER_SHARD) \
			--players $(SELFPLAY_PLAYERS) \
			--simulations $(SELFPLAY_SIMULATIONS) \
			--max-candidates $(SELFPLAY_MAX_CANDIDATES) \
			--max-turns $(SELFPLAY_MAX_TURNS) \
			--parallel $(SELFPLAY_PARALLEL_PER_SHARD) \
			--temperature-drop $(SELFPLAY_TEMPERATURE_DROP) \
			--seed $$seed \
			--output "$$out" \
			$$model_flag \
			2>&1 | tee "$$log" | sed "s/^/[shard-$$i] /" ) & \
	done; \
	wait
	@echo "selfplay done: $(RUN_ROOT)"

m4-selfplay-weekly: SELFPLAY_SHARDS=2
m4-selfplay-weekly: SELFPLAY_GAMES_PER_SHARD=25000
m4-selfplay-weekly: SELFPLAY_SIMULATIONS=256
m4-selfplay-weekly: SELFPLAY_PARALLEL_PER_SHARD=4
m4-selfplay-weekly: m4-selfplay

m4-merge:
	@mkdir -p "$(MERGED_DIR)"
	@cat "$(RUN_ROOT)"/shard-*/positions.ndjson > "$(MERGED_DIR)/positions.ndjson"
	@cat "$(RUN_ROOT)"/shard-*/games.ndjson > "$(MERGED_DIR)/games.ndjson"
	@echo "merged:"
	@wc -l "$(MERGED_DIR)/positions.ndjson" "$(MERGED_DIR)/games.ndjson"

m4-merge-cumulative:
	@echo "cumulative merge: window=$(TRAIN_CUMULATIVE_WINDOW)"
	@recent_runs=$$(ls -dt TrainingRuns/*/merged 2>/dev/null | head -$(TRAIN_CUMULATIVE_WINDOW)); \
	extra_flags=""; \
	for run in $$recent_runs; do \
		if [ "$$run" != "$(MERGED_DIR)" ] && [ -f "$$run/positions.ndjson" ]; then \
			extra_flags="$$extra_flags --data-extra $$run"; \
			echo "  + $$run"; \
		fi; \
	done; \
	echo "EXTRA_DATA_FLAGS=$$extra_flags" > "$(RUN_ROOT)/.cumulative_flags"

m4-train: m4-merge-cumulative
	@echo "train start: data=$(MERGED_DIR), architecture=$(TRAIN_ARCHITECTURE)"
	@extra_flags=""; \
	if [ -f "$(RUN_ROOT)/.cumulative_flags" ]; then \
		extra_flags=$$(grep EXTRA_DATA_FLAGS "$(RUN_ROOT)/.cumulative_flags" | cut -d= -f2-); \
	fi; \
	augment_flag=""; \
	if [ "$(TRAIN_AUGMENT)" = "true" ]; then \
		augment_flag="--augment"; \
	fi; \
	$(BIN) train \
		--data "$(MERGED_DIR)" \
		$$extra_flags \
		--limit $(TRAIN_LIMIT) \
		--label "$(TRAIN_LABEL)" \
		--architecture $(TRAIN_ARCHITECTURE) \
		--policy-arch $(TRAIN_POLICY_ARCH) \
		--policy-blend $(TRAIN_POLICY_BLEND) \
		--value-blend $(TRAIN_VALUE_BLEND) \
		--selected-boost $(TRAIN_SELECTED_BOOST) \
		--max-action-biases $(TRAIN_MAX_ACTION_BIASES) \
		--ridge $(TRAIN_RIDGE) \
		--epochs $(TRAIN_EPOCHS) \
		--lr $(TRAIN_LR) \
		--batch-size $(TRAIN_BATCH_SIZE) \
		$$augment_flag \
		--output "$(MODEL_PATH)"
	@echo "train done: model=$(MODEL_PATH)"

m4-eval:
	@if [ ! -f "$(BEST_MODEL)" ]; then \
		cp "$(MODEL_PATH)" "$(BEST_MODEL)"; \
		echo "best model was missing. seeded: $(BEST_MODEL)"; \
	fi
	@echo "eval start: A=$(BEST_MODEL), B=$(MODEL_PATH)"
	@$(BIN) eval \
		--model-a "$(BEST_MODEL)" \
		--model-b "$(MODEL_PATH)" \
		--games $(EVAL_GAMES) \
		--players $(EVAL_PLAYERS) \
		--simulations $(EVAL_SIMULATIONS) \
		--max-candidates $(EVAL_MAX_CANDIDATES) \
		--max-turns $(EVAL_MAX_TURNS) \
		--parallel $(EVAL_PARALLEL) \
		--seed $(EVAL_SEED) \
		--output "$(EVAL_REPORT)"
	@echo "eval done: report=$(EVAL_REPORT)"

m4-export:
	@echo "export start: model=$(MODEL_PATH)"
	@$(BIN) export \
		--model "$(MODEL_PATH)" \
		--output "$(EXPORT_DIR)"
	@echo "export done: dir=$(EXPORT_DIR)"

m4-promote:
	@cp "$(MODEL_PATH)" "$(BEST_MODEL)"
	@echo "promoted: $(MODEL_PATH) -> $(BEST_MODEL)"

m4-all: m4-selfplay m4-merge m4-train m4-eval m4-export
	@echo ""
	@echo "pipeline done"
	@echo "  run_root:   $(RUN_ROOT)"
	@echo "  model:      $(MODEL_PATH)"
	@echo "  eval:       $(EVAL_REPORT)"
	@echo "  export_dir: $(EXPORT_DIR)"

m4-loop:
	@bash scripts/loop.sh $(LOOP_COUNT) $(PROMOTE_THRESHOLD)
