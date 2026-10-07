test_that("the existing public export surface remains available", {
  expected_exports <- c(
    "build_body_pass2_structural",
    "build_registry_entry_from_analysis",
    "build_standardized_input",
    "cat_slowly",
    "classify_generation_interface",
    "coerce_path_segments",
    "common_error_blacklist",
    "complete_headers_for_pass2",
    "adaptive_feedback_experiment",
    "conversation_experiment",
    "conversation_experiment_with_feedback",
    "default_keyword_lexicon",
    "default_optional_keys",
    "detect_embedded_think_tag",
    "ensure_registry_header",
    "explain_alias",
    "extract_pass2_templates",
    "extract_usage_fields",
    "factorial_trial_experiment",
    "find_placeholder_path",
    "flat_key_to_regex",
    "flatten_json_paths",
    "format_registration_preview",
    "generate_llm_experiment_list",
    "generate_llm_factorial_experiment_list",
    "get_model_config",
    "get_registry_entry",
    "get_registry_path",
    "has_nonempty_text",
    "infer_role_mapping_from_body",
    "infer_structure_from_placeholder",
    "inject_optional_params",
    "is_invalid_candidate",
    "is_message_object",
    "json_get_by_path",
    "list_get_by_path",
    "llm_caller",
    "llm_register",
    "load_registry",
    "make_alias",
    "make_pass2_probe_inputs",
    "merge_defaults_for_probe",
    "multi_model_experiment",
    "normalize_history_messages",
    "normalize_path_key",
    "normalize_path_key_with_regex",
    "normalize_provider_label",
    "normalize_type_label",
    "probe_llm_streaming",
    "register_endpoint_offline",
    "register_endpoint_to_user_registry",
    "save_experiment_results",
    "score_candidates_ns",
    "score_candidates_st",
    "stream_reconstruct_text",
    "strip_optionals_from_body",
    "sub_placeholders",
    "trial_experiment",
    "update_progress_bar",
    "validate_experiment_config",
    "validate_registry_entry",
    "validate_registry_schema"
  )

  expect_setequal(getNamespaceExports("PsyLingLLM"), expected_exports)
})

test_that("critical public function signatures remain stable", {
  expect_identical(
    names(formals(llm_caller)),
    c(
      "model_key",
      "generation_interface",
      "api_url",
      "trial_prompt",
      "material",
      "system_content",
      "assistant_content",
      "api_key",
      "optionals",
      "stream",
      "role_mapping",
      "timeout",
      "return_raw",
      "debug",
      "..."
    )
  )
  expect_identical(formals(llm_caller)$optionals, quote(expr = ))
  expect_identical(
    names(formals(get_registry_entry)),
    c("model_key", "generation_interface", "path")
  )
  expect_identical(
    names(formals(get_model_config)),
    c("model_name", "registry")
  )
  expect_length(formals(load_registry), 0L)
})
