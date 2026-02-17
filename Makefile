BIN ?= ./.build/release/TrainerCLI

RUN_TS ?= $(shell date +%Y%m%d-%H%M%S)
RUN_ROOT ?= TrainingRuns/$(RUN_TS)
MERGED_DIR ?= $(RUN_ROOT)/merged
MODEL_PATH ?= Models/model-$(RUN_TS).json
BEST_MODEL ?= Models/model-best.json
EVAL_REPORT ?= Reports/eval-$(RUN_TS).json
EXPORT_DIR ?= Exports/export-$(RUN_TS)

SELFPLAY_SHARDS ?= 4
SELFPLAY_GAMES_PER_SHARD ?= 5000
SELFPLAY_PLAYERS ?= 4
SELFPLAY_SIMULATIONS ?= 256
SELFPLAY_MAX_CANDIDATES ?= 56
SELFPLAY_MAX_TURNS ?= 320
SELFPLAY_PARALLEL_PER_SHARD ?= 2
SELFPLAY_SEED_BASE ?= 10000

TRAIN_LIMIT ?= 2000000
TRAIN_LABEL ?= m4-$(RUN_TS)
TRAIN_POLICY_BLEND ?= 0.65
TRAIN_VALUE_BLEND ?= 0.70
TRAIN_SELECTED_BOOST ?= 1.2
TRAIN_MAX_ACTION_BIASES ?= 60000
TRAIN_RIDGE ?= 0.001

EVAL_GAMES ?= 3000
EVAL_PLAYERS ?= 4
EVAL_SIMULATIONS ?= 160
EVAL_MAX_CANDIDATES ?= 48
EVAL_MAX_TURNS ?= 320
EVAL_PARALLEL ?= 8
EVAL_SEED ?= 42

.PHONY: help format build-trainer prepare m4-selfplay m4-selfplay-weekly m4-merge m4-train m4-eval m4-export m4-promote m4-all

help:
	@echo "Usage:"
	@echo "  make build-trainer"
	@echo "  make m4-selfplay"
	@echo "  make m4-merge"
	@echo "  make m4-train"
	@echo "  make m4-eval"
	@echo "  make m4-export"
	@echo "  make m4-all"
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
	@end=$$(( $(SELFPLAY_SHARDS) - 1 )); \
	for i in $$(seq 0 $$end); do \
		seed=$$(( $(SELFPLAY_SEED_BASE) + $$i )); \
		out="$(RUN_ROOT)/shard-$$i"; \
		log="$(RUN_ROOT)/shard-$$i.log"; \
		mkdir -p "$$out"; \
		echo "  shard $$i -> $$out (seed=$$seed)"; \
		$(BIN) selfplay \
			--games $(SELFPLAY_GAMES_PER_SHARD) \
			--players $(SELFPLAY_PLAYERS) \
			--simulations $(SELFPLAY_SIMULATIONS) \
			--max-candidates $(SELFPLAY_MAX_CANDIDATES) \
			--max-turns $(SELFPLAY_MAX_TURNS) \
			--parallel $(SELFPLAY_PARALLEL_PER_SHARD) \
			--seed $$seed \
			--output "$$out" \
			> "$$log" 2>&1 & \
	done; \
	wait
	@echo "selfplay done: $(RUN_ROOT)"

m4-selfplay-weekly: SELFPLAY_SHARDS=8
m4-selfplay-weekly: SELFPLAY_GAMES_PER_SHARD=12500
m4-selfplay-weekly: SELFPLAY_SIMULATIONS=320
m4-selfplay-weekly: SELFPLAY_PARALLEL_PER_SHARD=1
m4-selfplay-weekly: m4-selfplay

m4-merge:
	@mkdir -p "$(MERGED_DIR)"
	@cat "$(RUN_ROOT)"/shard-*/positions.ndjson > "$(MERGED_DIR)/positions.ndjson"
	@cat "$(RUN_ROOT)"/shard-*/games.ndjson > "$(MERGED_DIR)/games.ndjson"
	@echo "merged:"
	@wc -l "$(MERGED_DIR)/positions.ndjson" "$(MERGED_DIR)/games.ndjson"

m4-train:
	@echo "train start: data=$(MERGED_DIR)"
	@$(BIN) train \
		--data "$(MERGED_DIR)" \
		--limit $(TRAIN_LIMIT) \
		--label "$(TRAIN_LABEL)" \
		--policy-blend $(TRAIN_POLICY_BLEND) \
		--value-blend $(TRAIN_VALUE_BLEND) \
		--selected-boost $(TRAIN_SELECTED_BOOST) \
		--max-action-biases $(TRAIN_MAX_ACTION_BIASES) \
		--ridge $(TRAIN_RIDGE) \
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
