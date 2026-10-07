ensure_psylingllm_directory <- function(path, label = "directory") {
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
      !nzchar(path)) {
    stop(sprintf("The %s path must be one non-empty string.", label),
         call. = FALSE)
  }
  if (dir.exists(path)) {
    return(invisible(path))
  }
  if (file.exists(path)) {
    stop(sprintf("Cannot create %s because a file exists at `%s`.", label, path),
         call. = FALSE)
  }
  created <- dir.create(
    path,
    recursive = TRUE,
    showWarnings = FALSE
  )
  if (!isTRUE(created) && !dir.exists(path)) {
    stop(sprintf("Failed to create %s `%s`.", label, path), call. = FALSE)
  }
  invisible(path)
}

replace_file_safely <- function(source, target, overwrite = TRUE) {
  if (!file.exists(source)) {
    stop("Replacement source file does not exist.", call. = FALSE)
  }
  if (file.exists(target) && !isTRUE(overwrite)) {
    stop("[PsyLingLLM] File already exists: ", target, call. = FALSE)
  }

  backup <- NULL
  if (file.exists(target)) {
    backup <- tempfile(
      pattern = ".psylingllm-backup-",
      tmpdir = dirname(target)
    )
    if (!file.rename(target, backup)) {
      stop("Failed to prepare the existing file for safe replacement: ",
           target, call. = FALSE)
    }
  }

  installed <- file.rename(source, target)
  if (!isTRUE(installed)) {
    rollback_ok <- is.null(backup) || file.rename(backup, target)
    detail <- if (isTRUE(rollback_ok)) {
      "The previous file was restored."
    } else {
      paste0("The previous file remains at `", backup, "`.")
    }
    stop("Failed to replace `", target, "`. ", detail, call. = FALSE)
  }

  if (!is.null(backup) && file.exists(backup)) {
    unlink(backup, force = TRUE)
  }
  invisible(target)
}
