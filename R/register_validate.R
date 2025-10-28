#' Compare two optional scalar strings (paths). Return a structured line and a boolean flag.
#' @param label Human-readable label, e.g., "NS respond_path"
#' @param p1    Pass-1 selected path (character(1) or NULL)
#' @param p2    Pass-2 selected path (character(1) or NULL)
#' @param NS    Is NS answer or not.
#' @return list(line=character(1), ok=logical(1))
compare_path_line <- function(label, p1, p2, NS=FALSE) {
  to_s <- function(x) if (is.null(x) || !nzchar(x)) "<none>" else x
  s1 <- to_s(p1); s2 <- to_s(p2)

  if ((is.null(p1) || !nzchar(p1)) && (is.null(p2) || !nzchar(p2)) && NS) {
    # both NS empty
    return(list(line = "\U00002757  NS respond_path missing in both Pass-1 and Pass-2 (required non-empty).", ok = FALSE))
  }

  if ((is.null(p1) || !nzchar(p1)) && (is.null(p2) || !nzchar(p2)) && !NS) {
    # both empty
    return(list(line = sprintf(" ~ %s: <none>", label), ok = TRUE))
  }

  if (identical(s1, s2)) {
    return(list(line = sprintf("\U00002705 %s consistent: %s", label, s1), ok = TRUE))
  }
  # differs
  return(list(
    line = sprintf("\U00002757 %s differs between Pass-1/Pass-2: %s \u2192 %s", label, s1, s2),
    ok   = FALSE
  ))

}


#' Render a structured "[Pass-2 Verified Ports]" report section.
#'
#' This report ONLY checks path consistency between Pass-1 and Pass-2 best picks.
#' If all paths are consistent, the section ends with a PASSED verdict.
#' Otherwise, it ends with a FAILED verdict and actionable guidance.
#'
#' @param pass1_paths list with fields:
#'   - ns_answer, ns_think, st_answer, st_think  (character(1) or NULL)
#' @param pass2_paths list with same fields as pass1_paths
#' @return character vector of lines (ready to cat/paste)
render_pass2_path_consistency_report <- function(pass1_paths, pass2_paths) {
  lines <- character()
  lines <- c(lines, "[Pass-2 Verified Ports]")

  # --- Skip thinking comparison when both ns/st answer & think are identical ---
  skip_think <- (
    !is.null(pass1_paths$ns_answer) && !is.null(pass1_paths$ns_think) &&
      identical(pass1_paths$ns_answer, pass1_paths$ns_think)
  ) || (
    !is.null(pass1_paths$st_answer) && !is.null(pass1_paths$st_think) &&
      identical(pass1_paths$st_answer, pass1_paths$st_think)
  )

  # --- Compare each key path ---
  cmp <- list(
    compare_path_line("NS respond_path", pass1_paths$ns_answer, pass2_paths$ns_answer,NS = TRUE),

    if (!skip_think)
      compare_path_line("NS thinking_path", pass1_paths$ns_think, pass2_paths$ns_think)
    else
      list(line = "\U00002699  NS thinking_path skipped (embedded <think> detected)", ok = TRUE),

    compare_path_line("ST delta_path", pass1_paths$st_answer, pass2_paths$st_answer),

    if (!skip_think)
      compare_path_line("ST thinking_delta_path", pass1_paths$st_think, pass2_paths$st_think)
    else
      list(line = "\U00002699  ST thinking_delta_path skipped (embedded <think> detected)", ok = TRUE)
  )

  # --- Aggregate results ---
  lines <- c(lines, vapply(cmp, `[[`, "", "line"))
  all_ok <- all(vapply(cmp, `[[`, TRUE, "ok"))

  # --- Verdict block ---
  if (all_ok) {
    lines <- c(
      lines,
      "",
      "\U00002705 All ports consistent between Pass-1 and Pass-2. Verification PASSED \U0001F947"
    )
  } else {
    if (is.null(pass1_paths$ns_answer) && is.null(pass2_paths$ns_answer)) {
      lines <- c(
        lines,
        "",
        "\U00002757 NS ports missing - verification FAILED.\n    Please check your registry configuration."
      )
    }else{
      lines <- c(
        lines,
        "",
        "\U00002757 Some ports differ or missing between Pass-1 and Pass-2. Verification FAILED."
      )
    }

  }

  lines
}




#' Validate structure of a registry entry
#'
#' Checks if key fields exist and have correct types.
#' Designed for both online and offline entries.
#'
#' @param entry List. Single model entry from registry.
#' @return Logical TRUE if valid; otherwise prints warnings.
#' @export
validate_registry_entry <- function(entry) {
  ok <- TRUE
  check_field <- function(cond, msg) {
    if (!cond) {
      message(" ! ", msg)
      ok <<- FALSE
    }
  }

  # Core structure
  check_field("provider" %in% names(entry), "Missing `provider` field")
  check_field("input" %in% names(entry), "Missing `input` section")
  check_field("output" %in% names(entry), "Missing `output` section")

  # Input
  inp <- entry$input
  check_field(!is.null(inp$default_url), "Missing input$default_url")
  check_field(!is.null(inp$headers), "Missing input$headers")
  check_field(!is.null(inp$body), "Missing input$body")

  # Output
  out <- entry$output
  check_field(!is.null(out$respond_path), "Missing output$respond_path")
  check_field(is.null(out$thinking_path) || identical(out$thinking_path, "~") || is.null(out$thinking_path),
              "thinking_path must be NULL or ~")

  # Token usage
  tp <- out$token_usage_path
  check_field(is.list(tp) && all(c("prompt","completion") %in% names(tp)),
              "token_usage_path must include prompt & completion")

  # Streaming
  s <- entry$streaming
  check_field(is.logical(s$enabled), "streaming$enabled should be logical TRUE/FALSE")
  check_field(is.character(s$delta_path), "streaming$delta_path should be list(\"...\") string")

  if (ok) {
    message("Registry entry structure valid.")
    return(TRUE)
  } else {
    message("ome issues detected. Please review messages above.")
    return(FALSE)
  }
}
