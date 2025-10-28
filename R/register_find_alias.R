#' Generate a compact alias for a model id
#'
#' Convert provider/model-style identifiers (e.g., "unsloth/gemma-3-4b-it",
#' "Alibaba-NLP/Tongyi-DeepResearch-30B-A3B", "llama-3.1-70b-instruct-128k")
#' into short, stable aliases by:
#' 1) taking the last path segment, lowercasing, tokenizing on non-alnum,
#' 2) removing size/context/quantization/packaging tokens,
#' 3) (optionally) keeping version tokens (major / major+minor / full),
#' 4) keeping meaningful mode/intent tokens (it/instruct/chat/flash/turbo/…),
#' 5) deduplicating and joining with "-".
#'
#' @param model_id Character scalar. Provider/model or plain name.
#' @param keep_version One of c("none","major","major_minor","full").
#'   "none" (default) drops version tokens; "major" keeps first integer only
#'   (e.g., llama-3.1 -> 3); "major_minor" keeps e.g., "3-1"; "full" keeps all.
#'
#' @return Character scalar alias (lowercase kebab-case).
#'
#' @examples
#' make_alias("unsloth/gemma-3-4b-it")
#' #> "gemma-it"
#' make_alias("meta-llama/llama-3.1-70b-instruct-128k", keep_version = "major")
#' #> "llama-3-instruct"
#' make_alias("mistralai/Mixtral-8x7B-Instruct-v0.1")
#' #> "mixtral-instruct"
#' make_alias("meituan-longcat/LongCat-Flash-Thinking-FP8")
#' #> "longcat-flash-thinking"
#' make_alias("deepseek-ai/DeepSeek-R1-Distill-Qwen-32B", keep_version = "none")
#' #> "deepseek-r1-distill-qwen"
#' @export
make_alias <- function(model_id, keep_version = c("none", "major", "major_minor", "full")) {
  keep_version <- match.arg(keep_version)

  stopifnot(is.character(model_id), length(model_id) == 1, nzchar(model_id))

  to_lower <- function(x) tolower(x)
  # normalize separators, keep alnum as tokens
  norm <- function(x) {
    x <- gsub("[^A-Za-z0-9]+", "-", x)
    x <- gsub("-+", "-", x)
    x <- gsub("(^-|-$)", "", x)
    x
  }

  # split to tokens
  last_seg <- basename(model_id)
  tokens0 <- strsplit(to_lower(norm(last_seg)), "-", fixed = TRUE)[[1]]
  tokens0 <- tokens0[nchar(tokens0) > 0]

  # Detect an embedded version inside the first token, e.g., "llama3.1", "qwen2.5"
  # Split it as base + version if present.
  split_embedded_version <- function(tok) {
    m <- regexec("^([a-z]+)(\\d+(?:\\.\\d+)*)$", tok)
    r <- regmatches(tok, m)[[1]]
    if (length(r) == 3) list(base = r[2], ver = r[3]) else list(base = tok, ver = NA_character_)
  }
  if (length(tokens0)) {
    sv <- split_embedded_version(tokens0[1])
    if (!is.na(sv$ver)) {
      tokens0[1] <- sv$base
      tokens0 <- c(tokens0[1], sv$ver, tokens0[-1])
    }
  }

  # Classification rules
  is_size_token <- function(t) grepl(
    "^((\\d+(?:\\.\\d+)?)b|\\d+x\\d+b|\\d+m)$", t, perl = TRUE
  )
  is_context_token <- function(t) grepl(
    "^(\\d+)(k|m)$", t, perl = TRUE
  )
  is_quant_or_precision <- function(t) grepl(
    "^(int\\d+|fp\\d+|bf16|q\\d+(_[a-z0-9_]+)?|gguf|gptq|awq|exl2|bnb)$", t, perl = TRUE
  )
  is_packaging <- function(t) grepl(
    "^(hf|mergekit|safetensors)$", t, perl = TRUE
  )
  is_train_method <- function(t) grepl(
    "^(sft|dpo|ppo|rlaif|rlhf|lora|qlora)$", t, perl = TRUE
  )
  # version-like tokens: "3", "3.1", "v1", "v3.2"
  is_version_token <- function(t) grepl(
    "^(v?\\d+(?:\\.\\d+){0,2})$", t, perl = TRUE
  )
  # keep set: mode/intent/capabilities that are semantically useful
  is_mode_token <- function(t) t %in% c(
    "it", "instruct", "chat", "base",
    "flash", "turbo", "mini", "small", "medium", "large", "xl", "xxl", "pro", "ultra",
    "vision", "vl", "multimodal",
    "code", "coder", "math",
    "thinking", "reasoning", "think", "r1", "distill",
    "deepresearch", "research", "flashthinking", "thinkingfp8" # allow odd variants
  )

  # Walk tokens and decide keep/drop
  kept <- character()
  version_seen <- FALSE
  version_tokens <- character()
  dropped_tbl <- list()  # keep some audit info

  for (t in tokens0) {
    reason <- NULL
    action <- NULL

    if (is_size_token(t)) {
      action <- "drop"; reason <- "size"
    } else if (is_context_token(t)) {
      action <- "drop"; reason <- "context"
    } else if (is_quant_or_precision(t)) {
      action <- "drop"; reason <- "quant/precision"
    } else if (is_packaging(t)) {
      action <- "drop"; reason <- "packaging"
    } else if (is_train_method(t)) {
      action <- "drop"; reason <- "training"
    } else if (is_version_token(t)) {
      # collect, add later according to keep_version
      action <- "version"
      version_seen <- TRUE
      version_tokens <- c(version_tokens, t)
    } else if (is_mode_token(t)) {
      action <- "keep"; reason <- "mode"
      kept <- c(kept, t)
    } else if (grepl("^[a-z]+$", t)) {
      action <- "keep"; reason <- "family/variant"
      kept <- c(kept, t)
    } else if (grepl("^[a-z0-9]+$", t)) {
      # mixed alnum (e.g., "a3b", "r1", "qwen2") -> keep
      action <- "keep"; reason <- "variant"
      kept <- c(kept, t)
    } else {
      action <- "drop"; reason <- "other"
    }

    dropped_tbl[[length(dropped_tbl) + 1]] <- list(token = t, action = action, reason = reason)
  }

  # Handle version policy
  add_version <- function(vs) {
    # normalize version tokens like v3.1 -> 3.1
    vs <- sub("^v", "", vs)
    if (keep_version == "none") return(character())
    if (!length(vs)) return(character())
    # choose the first version-like token as canonical
    main <- vs[1]
    nums <- strsplit(main, "\\.", fixed = TRUE)[[1]]
    if (keep_version == "major") {
      return(nums[1])
    } else if (keep_version == "major_minor") {
      return(paste(nums[1:min(2, length(nums))], collapse = "-"))
    } else {
      # full: replace dots with dashes
      return(gsub("\\.", "-", main))
    }
  }

  kept <- c(kept[1], add_version(version_tokens), kept[-1])

  # Deduplicate while preserving order
  kept <- kept[!duplicated(kept)]
  # Remove empties and join
  kept <- kept[nchar(kept) > 0]
  alias <- paste(kept, collapse = "-")
  alias <- gsub("-+", "-", alias)
  alias <- gsub("(^-|-$)", "", alias)

  alias
}



#' Explain how an alias was derived from a model id
#'
#' Returns a tibble describing each token, whether it was kept/dropped,
#' the reason category, and the final alias for auditing and debugging.
#'
#' @param model_id Character scalar.
#' @param keep_version One of c("none","major","major_minor","full").
#'
#' @return A tibble with columns: token, action, reason; attribute 'alias'.
#' @examples
#' explain_alias("meta-llama/llama-3.1-70b-instruct-128k", keep_version = "major")
#' @export
explain_alias <- function(model_id, keep_version = c("none", "major", "major_minor", "full")) {
  keep_version <- match.arg(keep_version)
  # Reuse make_alias internals by shadowing and capturing token audit
  .audit_env <- new.env(parent = emptyenv())

  # Local wrapper that captures per-token decisions
  make_alias_with_audit <- function(model_id, keep_version) {
    tokens_log <- list()
    log_add <- function(t, action, reason) {
      tokens_log[[length(tokens_log) + 1]] <<- list(token = t, action = action, reason = reason)
    }

    to_lower <- function(x) tolower(x)
    norm <- function(x) {
      x <- gsub("[^A-Za-z0-9]+", "-", x)
      x <- gsub("-+", "-", x)
      x <- gsub("(^-|-$)", "", x)
      x
    }
    last_seg <- basename(model_id)
    tokens0 <- strsplit(to_lower(norm(last_seg)), "-", fixed = TRUE)[[1]]
    tokens0 <- tokens0[nchar(tokens0) > 0]

    split_embedded_version <- function(tok) {
      m <- regexec("^([a-z]+)(\\d+(?:\\.\\d+)*)$", tok)
      r <- regmatches(tok, m)[[1]]
      if (length(r) == 3) list(base = r[2], ver = r[3]) else list(base = tok, ver = NA_character_)
    }
    if (length(tokens0)) {
      sv <- split_embedded_version(tokens0[1])
      if (!is.na(sv$ver)) {
        tokens0[1] <- sv$base
        tokens0 <- c(tokens0[1], sv$ver, tokens0[-1])
      }
    }

    is_size_token <- function(t) grepl("^((\\d+(?:\\.\\d+)?)b|\\d+x\\d+b|\\d+m)$", t, perl = TRUE)
    is_context_token <- function(t) grepl("^(\\d+)(k|m)$", t, perl = TRUE)
    is_quant_or_precision <- function(t) grepl("^(int\\d+|fp\\d+|bf16|q\\d+(_[a-z0-9_]+)?|gguf|gptq|awq|exl2|bnb)$", t, perl = TRUE)
    is_packaging <- function(t) grepl("^(hf|mergekit|safetensors)$", t, perl = TRUE)
    is_train_method <- function(t) grepl("^(sft|dpo|ppo|rlaif|rlhf|lora|qlora)$", t, perl = TRUE)
    is_version_token <- function(t) grepl("^(v?\\d+(?:\\.\\d+){0,2})$", t, perl = TRUE)
    is_mode_token <- function(t) t %in% c(
      "it", "instruct", "chat", "base",
      "flash", "turbo", "mini", "small", "medium", "large", "xl", "xxl", "pro", "ultra",
      "vision", "vl", "multimodal",
      "code", "coder", "math",
      "thinking", "reasoning", "think", "r1", "distill",
      "deepresearch", "research"
    )

    kept <- character()
    version_tokens <- character()

    for (t in tokens0) {
      if (is_size_token(t)) {
        log_add(t, "drop", "size")
      } else if (is_context_token(t)) {
        log_add(t, "drop", "context")
      } else if (is_quant_or_precision(t)) {
        log_add(t, "drop", "quant/precision")
      } else if (is_packaging(t)) {
        log_add(t, "drop", "packaging")
      } else if (is_train_method(t)) {
        log_add(t, "drop", "training")
      } else if (is_version_token(t)) {
        log_add(t, "version", "version")
        version_tokens <- c(version_tokens, t)
      } else if (is_mode_token(t)) {
        kept <- c(kept, t); log_add(t, "keep", "mode")
      } else if (grepl("^[a-z]+$", t)) {
        kept <- c(kept, t); log_add(t, "keep", "family/variant")
      } else if (grepl("^[a-z0-9]+$", t)) {
        kept <- c(kept, t); log_add(t, "keep", "variant")
      } else {
        log_add(t, "drop", "other")
      }
    }

    add_version <- function(vs) {
      vs <- sub("^v", "", vs)
      if (keep_version == "none") return(character())
      if (!length(vs)) return(character())
      main <- vs[1]
      nums <- strsplit(main, "\\.", fixed = TRUE)[[1]]
      if (keep_version == "major") {
        return(nums[1])
      } else if (keep_version == "major_minor") {
        return(paste(nums[1:min(2, length(nums))], collapse = "-"))
      } else {
        return(gsub("\\.", "-", main))
      }
    }

    kept <- c(kept[1], add_version(version_tokens), kept[-1])
    kept <- kept[!duplicated(kept)]
    kept <- kept[nchar(kept) > 0]
    alias <- paste(kept, collapse = "-")
    alias <- gsub("-+", "-", alias)
    alias <- gsub("(^-|-$)", "", alias)

    list(alias = alias, log = tokens_log)
  }

  out <- make_alias_with_audit(model_id, keep_version)
  df <- tibble::tibble(
    token  = vapply(out$log, `[[`, character(1), "token"),
    action = vapply(out$log, `[[`, character(1), "action"),
    reason = vapply(out$log, `[[`, character(1), "reason")
  )
  attr(df, "alias") <- out$alias
  df
}
