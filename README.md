**PsyLingLLM** is an experimental toolkit for studying **human-like language processing** with Large Language Models (LLMs) in **R**.  
It provides functions to **design, execute, and analyze** psycholinguistic, psychological, and educational experiments using LLMs.

---
- v0.3 Update: **New Registry System**<br>
The latest release introduces a comprehensive registry system that significantly streamlines model configuration and experimental setup. This architecture enhances reproducibility while maintaining flexibility across diverse LLM providers.<br>

    **YAML-Based Configuration Registry**<br>
    Structured Experiment Definitions: All model API parameters and interface specifications stored in standardized YAML format
    Version-Controlled Setups: Enable exact experiment replication through committed registry files
    Cross-Platform Compatibility: Consistent behavior across different computing environments
    Flexible Field Mapping: Adapts to proprietary response formats without manual configuration
    Custom Endpoint Support: Handles non-standard API structures from local deployments and proxy services
    
    **Pre-Configured Provider Templates**<br>
    Major Provider Support:  Ready to use and pre-optimized templates for major providers
    Standardized Interfaces: Unified access patterns across different API specifications
    Rapid Deployment: Quick-start configurations requiring minimal customization

    **Automatic Regist System**<br>
    Automated Registration Pipeline: A streamlined workflow systematically analyzes API endpoints, standardizes request templates, and generates optimized configuration files through intelligent path detection and structural inference.<br>
    Interactive Preview Interface: Prior to finalization, researchers can comprehensively review all details through a structured preview that highlights potential inconsistencies or missing elements.<br>

    Link：Prat II Register system
---

## 📖 Background

LLMs are increasingly used to study **human language processing**, **cognitive science**, and **education**.  
Yet, designing controlled experiments with LLMs often involves substantial work: creating structured prompts, randomizing trials, and collecting results consistently.

**PsyLingLLM**simplifies this process by providing an **R package** that seamlessly integrates:

- Flexible experiment designs: `factorial`, `repeated trials`, and `conversation-based` paradigms
- Automated API interactions with multiple LLM providers
- Structured data logging, including `responses`, `reasoning traces`, and `timing`
- Support for adaptive trials and feedback-driven experiments

This enables researchers to focus on theory and analysis rather than experiment logistics.

---

## 📥 Installation

To install PsyLingLLM directly from the GitHub repository, execute the following commands in your R environment:

```r
# Install devtools if not already available
install.packages("devtools")

# Install PsyLingLLM from the GitHub repository
devtools::install_github("HanMingPsy/PsyLingLLM-R")
```
Verification
```
After installation, verify successful installation by loading the package and checking its version:

```r
library(PsyLingLLM)
packageVersion("PsyLingLLM")
```

---
# 📚 Features

- ✅ **Registry-first Reproducibility**
      All experiment configurations — from model endpoints to parameter defaults — are stored in versioned YAML registries.
      This guarantees full transparency and reproducibility across updates, labs, or computing environments.
      Automatic endpoint detection and schema inference remove the need for manual API setup, letting you focus entirely on your experimental design.

- ✅ **Precise Experimental Control**
      PsyLingLLM treats LLMs like participants in a behavioral experiment.
      It supports single-trial presentation, randomization, controlled repetition — ensuring every response is collected under precisely defined conditions.
      This makes model evaluation quantitative, time-sensitive, and reproducible.

- ✅ **Factorial & Condition-based Design**  
      Design complex experiments without manual table manipulation.
      Built-in factorial expansion automatically generates all combinations of independent variables (e.g., Congruity × Language), while condition metadata keeps your datasets organized.
      Ideal for psycholinguistic, reasoning, or cognitive modeling studies that test interaction effects between multiple experimental factors.

- ✅ **Conversation & Adaptive Paradigms**  
      Move beyond single prompts to multi-turn dialogue experiments with persistent context and rolling message history.
      Implement adaptive or feedback-driven tasks, where the model’s next input depends on its previous response — enabling simulations of tutoring, learning, and cooperative reasoning.
      
- ✅ **Cross-model & Multilingual Benchmarking**  
      Run the same experiment across different LLMs and languages under identical protocols.
      Full UTF-8 and Excel/CSV compatibility ensures smooth multilingual data handling,
      Structured logging and schema-standardized outputs allow direct cross-model comparison — turning raw model runs into analyzable experimental data.

---

# 📑 Table of Contents

## Part I
- [1. Single-Trial Experiment](#1-single-trial-experiment)
- [2. Repeated Trials with Conditions](#2-garden-path-sentences-judgment-task)
- [3. Factorial Designs](#4-factorial-designs)
- [4. Conversation-based Experiments](#5-conversation-style-experiment)
- [5. Dynamic Feedback & Adaptive Difficulty](#6-conversation-experiment-with-feedback)
- [6. Multi-Model Comparisons](#7-multi-model-experiment)
- [7. Data Handling (CSV/XLSX, UTF-8 Safe)](#7-data-handling-csvxlsx-utf-8-safe)
## Part II
- [8. Registry System Overview](#1-single-trial-experiment)
- [9. Endpoint Registration & Auto-Discovery](#1-single-trial-experiment)
- [10. Provider-Agnostic Interface](#1-single-trial-experiment)
- [10. Configuration Management](#1-single-trial-experiment)


---


# Prat 1 Experiment System



## 🚀 Quick Start
### 🔑 Authentication and Model Setup

To run any experiment, you need to prepare the following three items **from your LLM provider**:

1. **API Key** – your personal access token.  
2. **Model Name** – the identifier of the model you want to call.  
3. **API URL** – the HTTP endpoint for requests.

### How to find them?
- **API Key**: Available in your provider's user dashboard under API Keys or Access Tokens
  e.g., `DeepSeek: https://api-docs.deepseek.com/`<br>
  `ChatGPT: https://platform.openai.com/api-keys`<br>
  `HuggingFace: https://huggingface.co/settings/tokens`
- **Model Name**: Check your provider's documentation for available models, names are case-sensitive.
    e.g., `DeepSeek: deepseek-chat, deepseek-coder`
    `OpenAI: gpt-5, gpt-4o, gpt-4o-mini`
- **API URL**: check the developer documentation of your provider.<br>
      Custom endpoints: Your provider's API endpoint URL (e.g., `https://api.deepseek.com/chat/completions` for DeepSeek chat interfaces)<br>
      Self-hosted models: Local server address (e.g., `http://localhost:8080/v1/chat/completions`)<br>
 **Note**: Registered official providers are automatically configured—no URL specification required.

⚠️ **Important**: Never expose your API keys in publicly accessible code. For enhanced security, consider store credentials as variables instead of save them in scripts. e.g.:

```r
        # Use variables
        deepseek_api_key <- "sk-**********"
        api_key = deepseek_api_key
```
Or 
```r
        # Use environment variables
        Sys.setenv(deepseek_api_key = "sk-**********")
        api_key = Sys.getenv("deepseek_api_key")
```

---

## 1. Single-Trial Experiment
`trial_experiment()` represents the most fundamental paradigm for testing LLM behavior, analogous to presenting one stimulus to a human participant in psychological research. 


```r
   library(PsyLingLLM)
   # Test material
   df <- data.frame(
     Material = c(
       "The cat sat on the ____.",           # English
       "这只猫咪坐在____上。",                # Chinese (Simplified)
       "Le chat était assis sur le ____.",   # French
       "El gato estaba sentado en el ____.", # Spanish
       "Die Katze saß auf dem ____.",        # German
       "Il gatto era seduto sul ____.",      # Italian
       "ネコが____の上に座っていました。",     # Japanese
       "고양이가 ____ 위에 앉아 있었습니다.",  # Korean
       "O gato estava sentado no ____.",     # Portuguese
       "Katten satt på ____.",               # Swedish
       "Кот сидел на ____."                  # Russian
     )
   )
   
   # Run test
   result <- trial_experiment(
     data = df,
     api_key = "your_api_key_here",
     model_key   = "your_model_here",
     api_url = "https://your_api_url_here",
     trial_prompt = "Please complete the blank in the sentence."
   )
   
   print(result$Response)
```
---

### 🖥️ Console Output & File Management

During `PsyLingLLM` experiment execution, the console output provides runtime feedback including:


<img width="1725" height="45" alt="image" src="https://github.com/user-attachments/assets/6b05da8f-2152-472e-95f3-52efef72a170" />



- `[██████░░░] 73%` → Progress bar showing the completion of all trials.
- `Trial 8/11` → Indicates the current trial number out of total trials.
- `ETA: 01:14` → Estimated time remaining (s).
- `- deepseek-reasoner` → The model used for this experiment.

Upon experiment completion, the console will display execution results and output file paths:


`[PsyLingLLM] Results saved: C:\Users\Documents\.psylingllm\results\deepseek-reasoner_20251101_224010.csv`


**Output File Management**
When no custom output_path is specified, results are automatically saved to the default directory: ~/.psylingllm. The system generates timestamped files:
deepseek-reasoner_20251101_221529.csv → Structured experimental data and model responses
deepseek-reasoner_20251101_221529.log → Detailed execution logs and diagnostic information


Default file Naming Convention:
`{model-name}_{YYYYMMDD}_{HHMMSS}.{extension}` ensures unique identification across multiple experimental runs.


### 📝 Result Data Structure

After running a trial experiment with `PsyLingLLM`, the results are returned as a `data.frame` or saved to `CSV/XLSX` like this:

| Run | Item | TrialPrompt | Material | Response | Think |
|-----|------|--------------|-----------|-----------|----------------|
| 1 | 1 | Please complete the blank in the sentence. | The cat sat on the ____. | The cat sat on the **mat**. | "This is a very common English sentence, often used as an example. The most typical completion is 'mat'..." |
| 2 | 2 | Please complete the blank in the sentence. | 这只猫咪坐在____上。 | 这只猫咪坐在沙发上。 | "Common things a cat might sit on include a chair, a mat, a bed, a sofa... I'll go with '沙发'." |
| 3 | 3 | Please complete the blank in the sentence. | Le chat était assis sur le ____. | Le chat était assis sur le **tapis**. | "The sentence is in French... 'tapis' is masculine and means 'mat' — a common choice." |
| 4 | 4 | Please complete the blank in the sentence. | El gato estaba sentado en el ____. | El gato estaba sentado en el **tejado**. | "'En el' requires a masculine noun... 'tejado' (roof) makes sense here." |
| 5 | 5 | Please complete the blank in the sentence. | Die Katze saß auf dem ____. | Die Katze saß auf dem **Dach**. | "'Auf dem Dach' means 'on the roof' — a standard example in German." |
| 6 | 6 | Please complete the blank in the sentence. | Il gatto era seduto sul ____. | Il gatto era seduto sul divano. | "'Sul' is used with masculine nouns... 'divano' (sofa) is natural and common." |
| 7 | 7 | Please complete the blank in the sentence. | ネコが____の上に座っていました。 | ネコがいすの上に座っていました。 | "The sentence means 'The cat was sitting on top of ___'... I'll use 'いす' (chair)." |
| 8 | 8 | Please complete the blank in the sentence. | 고양이가 ____ 위에 앉아 있었습니다. | 고양이가 의자 위에 앉아 있었습니다. | "Common options include '의자', '탁자', '바닥'... I'll choose '의자' (chair)." |
| 9 | 9 | Please complete the blank in the sentence. | O gato estava sentado no ____. | O gato estava sentado no **chão**. | "'No' combines 'em + o', so the noun must be masculine... 'chão' fits perfectly." |
| 10 | 10 | Please complete the blank in the sentence. | Katten satt på ____. | Katten satt på mattan. | "In Swedish, 'på' means 'on'... 'mattan' (the mat) is the definite form." |
| 11 | 11 | Please complete the blank in the sentence. | Кот сидел на ____. | Кот сидел на столе. | "'На' takes the prepositional case... 'стол' becomes 'на столе' (on the table)." |


and includes comprehensive diagnostic metadata and trial execution states:


| ModelName | TotalResponseTime | PromptTokens | CompletionTokens | TrialStatus | Streaming | Timestamp | RequestID |
|------------|------------------:|--------------:|-----------------:|-------------|------------|------------------|--------------------|
| deepseek-reasoner | 8.530571222 | 25 | 206 | SUCCESS | FALSE | 2025/11/1 22:15 | b6d5b351|
| deepseek-reasoner | 14.36554313 | 24 | 376 | SUCCESS | FALSE | 2025/11/1 22:15 | d8bfa8c1|
| deepseek-reasoner | 26.26069283 | 27 | 689 | SUCCESS | FALSE | 2025/11/1 22:16 | 2cbb1e4c|
| deepseek-reasoner | 49.05775499 | 28 | 1346 | SUCCESS | FALSE | 2025/11/1 22:17 | 68062a0d|
| deepseek-reasoner | 19.82083488 | 27 | 548 | SUCCESS | FALSE | 2025/11/1 22:17 | 7a9d3aa3|
| deepseek-reasoner | 29.26222396 | 27 | 794 | SUCCESS | FALSE | 2025/11/1 22:17 | 273a27f2|
| deepseek-reasoner | 36.12755489 | 29 | 977 | SUCCESS | FALSE | 2025/11/1 22:18 | 5041a156|
| deepseek-reasoner | 16.51271296 | 30 | 436 | SUCCESS | FALSE | 2025/11/1 22:18 | a71ca7e3|
| deepseek-reasoner | 42.01539993 | 27 | 1074 | SUCCESS | FALSE | 2025/11/1 22:19 | 9acc1843|
| deepseek-reasoner | 33.07628107 | 25 | 900 | SUCCESS | FALSE | 2025/11/1 22:20 | da315652|
| deepseek-reasoner | 17.22883201 | 25 | 465 | SUCCESS | FALSE | 2025/11/1 22:20 | 1c5f8f25|

**Column Explanations:**

**Run** → Global sequential index for each trial.  
**Item** → Identifier of the presented stimulus or sentence item.  
**TrialPrompt** → The instruction or task prompt shown to the model.  
**Material** → The sentence, phrase, or experimental context the model responds to.  
**Response** → The final completion or answer produced by the model.  
**Think** → A short excerpt of the model’s reasoning trace (if available), useful for psycholinguistic or cognitive analysis.  

**ModelName** → The name or identifier of the large language model used (e.g., `deepseek-reasoner`).  
**TotalResponseTime** → Total time in seconds taken by the model to generate a full response.  
**PromptTokens** → Number of tokens in the input prompt.  
**CompletionTokens** → Number of tokens produced in the model’s output.  
**TrialStatus** → Execution result of the trial.  
**Streaming** → Indicates whether the response was generated using streaming mode.  
**Timestamp** → timestamp of when the trial was completed.  
**RequestID** → Unique identifier assigned to the request for reproducibility and traceability.  

Leran more in Schema section


---


## ⚙️Full Function Arguments: `trial_experiment()`
#### Core Experiment Parameters
- **`model_key`** → Registry identifier
   >Specifies the pre-configured model entry from the registry (e.g., `deepseek-chat` or `deepseek-chat@proxy`).
   >
- **`generation_interface `** → API interface type
   >Defines the interaction protocol; defaults to "chat/completion" for conversational interfaces.
   >
- **`api_key`** → Authentication credentials
   >Provider-specific API key for service access.
   >
- **`api_url`** → Endpoint override
   >Optional custom API URL; required for non-official providers.
   >
- **`data`** → The experiment materials. Can be a `data.frame` or a CSV/XLSX file.  
   >The experimental materials to be used for generating the LLM trial table. Can be a `data.frame`, or a path to a `.csv`, `.xls`, or `.xlsx` file.
   >
   >**Supported Input Formats**
   >
   > `PsyLingLLM` will automatically detect whether your data input is:
   >
   >`CSV file (.csv)`
   >Read using readr::read_csv() (UTF-8 safe).
   >
   >PsyLingLLM will automatically checks for non-UTF-8 encodings.
   >If non-UTF-8 characters (e.g., smart quotes, special symbols) are detected, they are automatically converted via stringi::stri_enc_toutf8().
   >A warning is issued when conversion occurs.
   >If encoding issues persist, it is recommended to save the file as Excel (.xlsx) instead.
   >
   >`Excel file (.xls, .xlsx)`
   >Read with readxl::read_excel()
  >
  >`R data.frame`
  >If a data frame is already loaded or generated in R, it will be used directly.
  >
  >`R data.frame`
  >Directly passed in if already loaded or generated in R.Useful when you pre-process or dynamically create stimuli.
  >
  >**Required Column**<br>
  >`Material` the experimental stimulus (sentence, word, text).<br>
  >This column is automatically recognized if your input has no headers:
  >If the first column of your CSV/data.frame has no name, it will be treated as Material.<br>
  >
  >**Automatically Added Columns**<br>
  >If these columns are missing from your input data, the system will automatically generate them:<br>
  >`Item` Sequential item number assigned to each row<br>
  >`Run` Trial index after repetitions and randomization<br>
  >`TrialPrompt` Prompt applied to trials<br>
  >
  >**Optional Columns**<br>
  > `Condition`: Experimental factors (e.g., Congruity, Difficulty)<br>
  >  Columns matching `Condition` or `condition` patterns receive priority placement. You need to name columns starting with (e.g., `condition1`, `Condition_congruity`)<br>
  >  `Custom Columns`: Add any additional columns to your dataset - all custom columns are preserved through the experimental pipeline.(e.g., correctresponse)<br>
  >  Columns organized as: Core → Conditions → Content → Custom
  >
  >  Link:Learn more in Data Handling section
#### Experiment Control Parameters
- **`repeats`** → The repeats parameter controls how many times the entire experiment dataset (all rows in data) should be duplicated. Optional (defualt = 1). 
   >How it works
   ```r
         df <- df[rep(seq_len(nrow(df)), repeats), , drop = FALSE]
   ```
   >This means that every trial in your dataset will be repeated repeats times.
   >
   >For example:
   >
   >Suppose you have 10 rows of stimuli:
   ```r
         df <- data.frame(
           Item = 1:10,
           Material = paste("Sentence", 1:10)
         )
   ```
   >If you set repeats = 3, each row will be copied 3 times:
   >
   > | Run | Item | Material    |
   > |-----|------|-------------|
   > | 1 | 1    | Sentence 1  |
   > | 2 | 2    | Sentence 2  |
   > | … | …    | …           |
   > | 10 | 10   | Sentence 10 |
   > | 11 | 1    | Sentence 1  |
   > | 12 | 2    | Sentence 2  |
   > | … | …    | …           |
   > | 20 | 10   | Sentence 10 |
   > | 21 | 1    | Sentence 1  |
   > | 22 | 2    | Sentence 2  |
   > | … | …    | …           |
   > | 30 | 10   | Sentence 10 |
   >
- **`random`** → Logical flag to control the order of trials.
   >`TRUE` → trials are shuffled randomly.
   >`FALSE` (default) → trials are kept in sequential order.
   >
- **`stream`** → Logical flag to control streaming output from the LLM. <br>
   > The stream parameter determines whether the model should return responses incrementally (token by token) or all at once.<br>
   > `TRUE` → streaming enabled; partial tokens are returned as they are generated.<br>
   > `FALSE` → standard non-streaming behavior; the full response is returned after completion.<br>
   > NULL (default) → PsyLingLLM uses the registry-defined (if support SSE then TRUE) default for the selected model.<br>
   > _note_: If stream = TRUE but the selected model does not support streaming, PsyLingLLM will ignore this setting and fall back to non-streaming mode.<br>
   > _note_: `FirstTokenLatency` is only available when `stream = TRUE`.<br>
   > 
- **`trial_prompt`** → A trial-level instruction applied to each experimental trial. Can be a single string or a per-row field in your data (optional).
  >The `trial_prompt` defines the task instruction presented to the model **together** with each stimulus (Material).<br>
  >It is combined with the stimulus text during request construction to form the user message for the LLM.<br>
     >**Examples:**<br>
     >`trial_prompt <- "Judge if the following sentence is grammatical:"`<br>
     >`Material <- "The cats sits on the mat."`<br>
     >The message sent to the LLM:<br>
     >`"Judge if the following sentence is grammatical: The cats sits on the mat."`<br>
  >When a `TrialPrompt` column **exists** in your dataset, its value takes precedence over the `trial_prompt` argument.<br>
  >If both are missing, an empty string is used by default.<br>
  >The `trial_prompt` applies to **all** trials unless overridden per row.<br>
  >
  
- **`system_content`** → Optional system-level instruction (system prompt) that defines the LLM’s behavior or global context during the experiment.<br>
   >The `system_content` argument specifies the system message sent to the model before any user message or stimulus.<br>
   >It controls how the model interprets and responds to experimental inputs, shaping the overall behavior of the assistant (e.g., tone, task, perspective).<br>
   >
   >Used in chat-based interfaces. It is sent as the **first system message** in the conversation, providing the model with instructions on how to act.<br>
   >This parameter is ignored only when the model template does not support system roles, in which case a one-time warning is issued.
   >
   >Researchers can use `system_content` to:<br>
   > Standardize responses across trials<br>
   > Manipulate the experimental context<br>
   > Create conditions that test different cognitive or linguistic scenarios<br>
   >
   > **Examples:**<br>
   > `"You are a participant in a psychology experiment."`<br>
   > `"You are a child learning English."` (simulate a learner)  <br>
   > `"You are a bilingual speaker fluent in English and Japanese."` (simulate bilingual processing)  <br>
   > `"Always respond in JSON with fields { 'judgment': <Yes/No>, 'confidence': <0-1> }."`  <br>
   >
- **`assistant_content`** → Optional seed messages provided to the assistant before each trial. list of message objects (`list(role=..., content=...)`).<br>
   >The `assistant_content` argument allows you to include pre-defined assistant messages.
   >It simulates prior dialogue history or “context examples” in multi-turn or instruction-following settings.
   >The argument is fully compatible with the registry-defined role structure (e.g., `system`, `user`, `assistant`) and is automatically normalized before sending the request to the LLM.
   >
- **`role_mapping`** → Optional mapping of abstract conversation roles (system, user, assistant) to the provider’s native role labels defined in the model’s API schema.<br>
   >The `role_mapping` parameter specifies how PsyLingLLM translates between its internal role names and the role identifiers expected by your LLM provider’s API.<br>
   >In most cases, you **do not need to specify** this argument manually —PsyLingLLM automatically uses the default role mapping defined in the model’s **registry entry**.<br>
   >You may optionally supply a custom mapping to **override** the registry defaults, forcing PsyLingLLM to use your specified `role_mapping` instead.<br>
   >**Example:**<br>
   ```r
         role_mapping = list(
           user = "human",
           system = "system",
           assistant = "assistant"
         )
   ```
   >_Note_: If your custom mapping does not match the provider’s expected role labels, the request may fail or certain message parts (e.g., `system` or `assistant` prompts) may be ignored by the model.
   >
- **`optionals`** → Optional named list controlling optional parameters for the LLM request (**except** stream).<br>
   >The `optionals` argument allows you to specify **user-provided optional fields** that may be included in the request body if supported by the model registry.<br>
   >PsyLingLLM uses a tri-state logic to handle these optionals:<br>
   >`Missing (not supplied)` → PsyLingLLM uses the registry defaults (input.optional_defaults) if present; otherwise, no optional parameters are sent.<br>
   >`NULL` → Do not send any optional parameters; the API defaults are used.<br>
   >`Named list` → Only the keys you provide are injected into the request; registry defaults are not merged.<br>
   >
   >**OpenAI Common Optionals**<br>
      `max_tokens`	Controls the length of the model’s response. Useful for experiments where you want consistent response size or to avoid overly long outputs that may bias response times or token-based measures.<br>
      `temperature`	Sampling temperature (0–2); Higher temperature increases variability in responses, useful for studying model creativity or variability in judgments. Low temperature ensures deterministic, reproducible outputs for controlled experiments.<br>
      `top_p`	Nucleus sampling probability (0–1).Together with temperature, controls response diversity. Useful in experiments examining model uncertainty or probabilistic decision-making.<br>
      `presence_penalty`	Penalizes new tokens based on presence in prior text (−2.0–2.0).Reduces repetitive responses. Useful in multi-turn experiments where repeated wording could confound response evaluation.<br>
      `frequency_penalty`	Penalizes new tokens based on frequency in prior text (−2.0–2.0).Encourages variety in responses. Helps experimental designs where lexical diversity is relevant, e.g., studying sentence generation or semantic novelty.<br>
   >
   >**Example:**<br>
   ```r
        optionals = list(
          max_tokens = 150,
          temperature = 0.7,
          top_p = 0.9
        )
   ```
   >

#### Other Parameters
- **`output_path`** → Optional file or directory path where PsyLingLLM saves experiment results and logs.
   >The `output_path` argument specifies **where PsyLingLLM writes experiment results and logs**.<br>
   >If not provided (NULL), PsyLingLLM automatically creates a default directory at `~/.psylingllm/results` and generates a timestamped filename in the format {model}_{YYYYMMDD_HHMMSS}.csv.<br>
   >You can provide either:
   >a **file path** (e.g., "results/my_experiment.csv")<br>
   >- a **directory path** (e.g., "results/", auto-naming enabled).<br>
   >
   > The function automatically chooses the save method based on file extension:<br>
   > `.csv` → uses `readr::write_excel_csv()` (UTF-8 encoded)<br>
   > `.xls / .xlsx` → uses `writexl::write_xlsx()` <br> 
   > unsupported or missing extension → defaults to .csv and appends it automatically<br>
   >If the target directory does not exist, it will be created recursively.<br>
   >  
   >After saving, PsyLingLLM prints a confirmation message to the console showing the full path of the saved file.<br>
   >Example auto-generated file:`~/.psylingllm/results/gpt-4o_20251103_134210.csv`<br>
   >Corresponding logs are automatically written to the same location with a .log extension.<br>
   >
- **`timeout`** → Integer value specifying the maximum time (in seconds) allowed for each LLM API request.<br>
   >The `timeout` parameter sets the upper limit for how long PsyLingLLM waits for a model response before aborting the request.<br>
   >- `Default` → 120 seconds unless overridden by a global option.<br>
   >
   >If the model does not respond within this duration, the trial is automatically marked as a timeout error (`TrialStatus = "TIMEOUT"`).<br>
   >This ensures that a single slow or unresponsive API call does not block the entire experiment run.<br>
   >
- **`overwrite`** → Logical flag indicating whether to overwrite existing output files.<br>
   >The overwrite parameter controls whether `PsyLingLLM` should replace an existing result file when writing experiment outputs via `output_path`.<br>
   >  
   >`TRUE` (default) → overwrite existing files if they already exist.<br>
   >`FALSE` → throw an error if the file already exists, preventing accidental data loss.<br>
   >   
   >This parameter is useful when you want to preserve previous experiment runs or enforce explicit versioning of output files.<br>
   >
- **`delay`** → Pause time (in seconds) between trials.<br>
   >The delay parameter introduces a controlled time interval between successive API requests.<br>
   >   
   >- `Default` is `0` (no delay).<br>
   >- Use a positive value (e.g., `delay = 1.5`) to insert a fixed pause between trials.<br>
   >
   >This can be useful in experiments where:<br>
      >API rate limits must be respected (e.g., OpenAI or Anthropic quotas).<br>
      >Controlled timing between stimuli is required (e.g., simulating human pacing).<br>
      >You want to prevent server overload during batch trials.<br>
   >   
   >The delay applies after each trial (or conversation turn) and before the next request begins.<br>
   >
- **`return_raw`** → Logical flag indicating whether to include raw request and response objects in the returned results.<br>
   >The return_raw parameter controls whether PsyLingLLM should attach the complete raw data for each API call — including the request body, headers, and raw response text — to the output data frame.<br>
   >`FALSE` (default) → returns only structured trial results conforming to PsyLingLLM_Schema.<br>
   >`TRUE` → adds additional columns containing the full raw request and response payloads for each trial.<br>
   >This option is useful for debugging, model comparison, or advanced post-hoc analyses where you need to inspect the exact input/output exchanged with the LLM API.<br>

  
---
<br>
<br>
<br>

## 2. Garden Path Sentences Judgment Task
This example demonstrates how to conduct a repeated-trial psycholinguistic experiment using the `trial_experiment()` function in **PsyLingLLM**.<br>
The task is based on the classical Garden Path Sentences paradigm, widely used to study syntactic reanalysis and semantic plausibility judgments.<br>

- 🧩 **Input Materials**<br>
First, import the example stimulus set from the package presets:<br>
```r
garden_path_sentences <- system.file("extdata", "garden_path_sentences.csv", package = "PsyLingLLM")
```
You will get:

| Item | Condition   | Material                              | TrialPrompt                                   |
|------|-------------|---------------------------------------|-----------------------------------------------|
| 1    | GardenPath  | The old man the boats.                | Does the following sentence make sense? (Y/N) |
| 2    | GardenPath  | The horse raced past the barn fell.   | Does the following sentence make sense? (Y/N) |
| 3    | GardenPath  | Fat people eat accumulates.           | Does the following sentence make sense? (Y/N) |
| 4    | GardenPath  | The man whistling tunes pianos.       | Does the following sentence make sense? (Y/N) |
| 5    | Control     | The young man watches the boats.      | Does the following sentence make sense? (Y/N) |
| 6    | Control     | The cat napping on the sofa purred.   | Does the following sentence make sense? (Y/N) |
| 7    | Control     | The young man watches the boats.      | Does the following sentence make sense? (Y/N) |
| 8    | Control     | The cat napping on the sofa purred.   | Does the following sentence make sense? (Y/N) |
| 9    | Anomalous   | The clever dust the furniture.        | Does the following sentence make sense? (Y/N) |
| 10   | Anomalous   | The cake baked in the oven laughed.   | Does the following sentence make sense? (Y/N) |
| 11   | Anomalous   | Stone workers cut precisely floats.   | Does the following sentence make sense? (Y/N) |
| 12   | Anomalous   | The student considering ideas clouds. | Does the following sentence make sense? (Y/N) |

This dataset contains **three experimental conditions**:<br>
`GardenPath` — syntactically ambiguous sentences that initially mislead the parser (e.g., The old man the boats).<br>
`Control` — unambiguous and semantically coherent sentences (e.g., The young man watches the boats).<br>
`Anomalous` — grammatically valid but semantically implausible sentences (e.g., The cake baked in the oven laughed).<br>
Each condition includes 4 items, and we set the experiment to repeat twice, yielding a total of 3 × 4 × 2 = 24 randomized trials.<br>

-⚙️**Running the Experiment**
```r
system_content =
  "You are a participant in a psychology experiment.
Your task is to answer the following questions with ONLY a single character: Y for Yes or N for No.
Do not provide any other text, explanation, or punctuation."

Res <- trial_experiment(
  data = garden_path_sentences,
  api_key = api_key,
  model_key = model,
  system_content = system_content,
  random = TRUE,
  stream = TRUE,
  repeats  = 2
)
```
During execution, a real-time progress bar will display trial progress and model status:<br>
`[████████████████████████████████████████] 100% Trial 24/24 - ETA: 00:00 - deepseek-reasoner`<br>
Upon completion, the full trial results are automatically saved to the default results directory:<br>
`[PsyLingLLM] Results saved: C:\Users\<username>\Documents\.psylingllm\results\deepseek-reasoner_20251105_153054.csv`<br>

-**Inspecting the Results**
The output `CSV` file (or dataframe `Res`) contains structured records for each trial, including columns such as:<br>

| Run | Item | Condition  | TrialPrompt                                   | Material                              | Response | ThinkExcerpt | ModelName | TotalResponseTime | FirstTokenLatency | PromptTokens | CompletionTokens | TrialStatus | Streaming | Timestamp | RequestID |
|-----|------|-----------|-----------------------------------------------|----------------------------------------|---------|--------------|-----------|-----------------|-----------------|--------------|-----------------|------------|----------|-----------|-----------|
| 1   | 3    | GardenPath | Does the following sentence make sense? (Y/N) | Fat people eat accumulates.            | N       | Recognizes grammatical error; interprets intended meaning (“The fat that people eat accumulates”); concludes it’s ungrammatical → N. | deepseek-reasoner | 13.24165797 | 0.850236893 | 63 | 335 | SUCCESS | TRUE | 2025/11/5 21:44 | bb33b1d5-f470-4391-a51f-69d75e46933e |
| 2   | 2    | GardenPath | Does the following sentence make sense? (Y/N) | The horse raced past the barn fell.    | N       | Identifies as a classic garden path sentence; recognizes structural ambiguity; initially confusing → N. | deepseek-reasoner | 24.77416396 | 1.013739824 | 66 | 623 | SUCCESS | TRUE | 2025/11/5 21:44 | 4660d6b6-b3a4-4ae0-9b66-69e914e15151 |
| 3   | 7    | Control    | Does the following sentence make sense? (Y/N) | Dust people stir up settles.           | Y       | Parses as “The dust that people stir up settles”; interprets as grammatical and meaningful → Y. | deepseek-reasoner | 10.90155888 | 0.749494076 | 65 | 268 | SUCCESS | TRUE | 2025/11/5 21:44 | 95e6f0c5-a79a-4c68-afc0-9e815ae2aa25 |
| 4   | 6    | Control    | Does the following sentence make sense? (Y/N) | The cat napping on the sofa purred.    | Y       | Finds sentence grammatically correct and semantically coherent → Y. | deepseek-reasoner | 11.68674183 | 1.829277039 | 68 | 257 | SUCCESS | TRUE | 2025/11/5 21:44 | 2e3eedee-b730-4803-a304-5745649a7de6 |
| 5   | 12   | Anomalous  | Does the following sentence make sense? (Y/N) | The student considering ideas clouds.  | N       | Detects missing main verb; unclear predicate; semantically incomplete → N. | deepseek-reasoner | 23.54776788 | 0.937865019 | 64 | 583 | SUCCESS | TRUE | 2025/11/5 21:45 | 8abab036-25f0-4284-860c-84a1c0af8e73 |
| 6   | 5    | Control    | Does the following sentence make sense? (Y/N) | The young man watches the boats.       | Y       | Clear subject–verb–object structure; grammatically and logically sound → Y. | deepseek-reasoner | 7.606292963 | 0.832577944 | 65 | 179 | SUCCESS | TRUE | 2025/11/5 21:45 | 4da0ed48-a3b1-467d-bce5-fa342bd5451a |
| 7   | 4    | GardenPath | Does the following sentence make sense? (Y/N) | The man whistling tunes pianos.        | N       | Ambiguous structure; likely missing punctuation; as written ungrammatical → N. | deepseek-reasoner | 22.22325683 | 0.751473904 | 66 | 575 | SUCCESS | TRUE | 2025/11/5 21:45 | f68e9824-7451-4a43-89e3-cd309b4ec80c |
| 8   | 1    | GardenPath | Does the following sentence make sense? (Y/N) | The old man the boats.                 | Y       | Recognizes it as a valid but deceptive garden path form; grammatically valid → Y. | deepseek-reasoner | 27.53471494 | 1.098387003 | 64 | 694 | SUCCESS | TRUE | 2025/11/5 21:46 | a9a4460d-5107-4a7b-8fac-24b972853008 |
| 9   | 6    | Control    | Does the following sentence make sense? (Y/N) | The cat napping on the sofa purred.    | Y       | Recognizes grammatical and semantic coherence; depicts a plausible event → Y. | deepseek-reasoner | 8.194425106 | 0.719024897 | 68 | 197 | SUCCESS | TRUE | 2025/11/5 21:46 | 0aa3522b-a588-4ef8-89d9-33aca36a2a85 |
| 10  | 1    | GardenPath | Does the following sentence make sense? (Y/N) | The old man the boats.                 | Y       | Identifies as a garden path structure; parses “The old” as noun phrase (elderly people) and “man” as verb; grammatically valid → Y. | deepseek-reasoner | 27.29363394 | 0.678291082 | 64 | 702 | SUCCESS | TRUE | 2025/11/5 21:46 | 029befd8-f1c0-4aac-972d-2bfc0ffaf6ac |
| 11  | 3    | GardenPath | Does the following sentence make sense? (Y/N) | Fat people eat accumulates.            | N       | Detects grammatical error and missing subject/object relation; interprets intended meaning (“fat that people eat accumulates”) → N. | deepseek-reasoner | 12.98447394 | 1.055468798 | 63 | 312 | SUCCESS | TRUE | 2025/11/5 21:46 | c3568f34-4165-4b87-a1f4-aada2c899d4e |
| 12  | 2    | GardenPath | Does the following sentence make sense? (Y/N) | The horse raced past the barn fell.    | N       | Notes classic garden path sentence; recognizes syntactic ambiguity; confusing structure → N. | deepseek-reasoner | 20.41931701 | 0.797111034 | 66 | 521 | SUCCESS | TRUE | 2025/11/5 21:47 | 3a2b9ef4-162b-4589-8d1b-23619fbcbf8e |
| 13  | 11   | Anomalous  | Does the following sentence make sense? (Y/N) | Stone workers cut precisely floats.    | N       | Analyzes word order (“cut precisely floats”) as ungrammatical; finds semantic mismatch (“cut floats”) → N. | deepseek-reasoner | 43.22063398 | 1.764032841 | 64 | 1086 | SUCCESS | TRUE | 2025/11/5 21:48 | 7ba40a69-4103-437f-a22d-fb38d128f854 |
| 14  | 10   | Anomalous  | Does the following sentence make sense? (Y/N) | The cake baked in the oven laughed.    | N       | Grammatically fine but semantically absurd (cakes cannot laugh) → N. | deepseek-reasoner | 16.3105619 | 0.911508083 | 66 | 397 | SUCCESS | TRUE | 2025/11/5 21:48 | 92a85d68-91a6-47f9-93e1-23c12f793517 |
| 15  | 8    | Control    | Does the following sentence make sense? (Y/N) | The woman reading books knits.         | Y       | Parses reduced relative clause (“who is reading books”); grammatical and meaningful → Y. | deepseek-reasoner | 17.07503605 | 1.545840979 | 65 | 412 | SUCCESS | TRUE | 2025/11/5 21:48 | 3ec47ef7-8e5a-4fb8-8b5a-56d694f82674 |
| 16  | 5    | Control    | Does the following sentence make sense? (Y/N) | The young man watches the boats.       | Y       | Straightforward subject–verb–object; syntactically and semantically coherent → Y. | deepseek-reasoner | 9.265040159 | 0.781780005 | 65 | 227 | SUCCESS | TRUE | 2025/11/5 21:48 | cbbe05a2-1b99-4af0-a3c7-cc3b43bfbad4 |
| 17  | 9    | Anomalous  | Does the following sentence make sense? (Y/N) | The clever dust the furniture.         | N       | “The clever” not a standard noun phrase; verb-object unclear; does not make sense → N. | deepseek-reasoner | 16.87882781 | 0.929712057 | 64 | 428 | SUCCESS | TRUE | 2025/11/5 21:49 | aca51c8d-507a-480f-9a53-5f2b34335475 |
| 18  | 9    | Anomalous  | Does the following sentence make sense? (Y/N) | The clever dust the furniture.         | N       | Same as above; ungrammatical; meaning unclear → N. | deepseek-reasoner | 14.84319496 | 0.570966959 | 64 | 391 | SUCCESS | TRUE | 2025/11/5 21:49 | 25a29a58-6f23-4146-91ab-329c17d4969d |
| 19  | 11   | Anomalous  | Does the following sentence make sense? (Y/N) | Stone workers cut precisely floats.    | N       | Repeats prior anomalous sentence; word order and semantics problematic → N. | deepseek-reasoner | 22.27108002 | 1.033094168 | 64 | 569 | SUCCESS | TRUE | 2025/11/5 21:49 | 157e4b5d-d856-4f20-96e7-7cc5ba77fdcb |
| 20  | 8    | Control    | Does the following sentence make sense? (Y/N) | The woman reading books knits.         | Y       | Same as previous occurrence; grammatical and coherent → Y. | deepseek-reasoner | 8.125644922 | 0.600242138 | 65 | 197 | SUCCESS | TRUE | 2025/11/5 21:49 | f32ce618-ebe3-47fe-8327-dfb9b3eebb06 |
| 21  | 7    | Control    | Does the following sentence make sense? (Y/N) | Dust people stir up settles.           | Y       | Same as previous occurrence; parses correctly → Y. | deepseek-reasoner | 12.375669 | 0.665314913 | 65 | 319 | SUCCESS | TRUE | 2025/11/5 21:49 | edfe9918-0e8b-4456-abf7-07130d5093df |
| 22  | 10   | Anomalous  | Does the following sentence make sense? (Y/N) | The cake baked in the oven laughed.    | N       | Same as previous occurrence; semantically absurd → N. | deepseek-reasoner | 19.31047702 | 1.418601036 | 66 | 473 | SUCCESS | TRUE | 2025/11/5 21:50 | 5e3eb99d-6937-40aa-8b8b-02fd38b51ce7 |
| 23  | 12   | Anomalous  | Does the following sentence make sense? (Y/N) | The student considering ideas clouds.  | N       | Same as previous occurrence; incomplete sentence → N. | deepseek-reasoner | 19.02880406 | 0.945214033 | 64 | 488 | SUCCESS | TRUE | 2025/11/5 21:50 | f1bf4211-1a3a-4949-98e5-0caf277aa700 |
| 24  | 4    | GardenPath | Does the following sentence make sense? (Y/N) | The man whistling tunes pianos.        | N       | Same as previous occurrence; ungrammatical → N. | deepseek-reasoner | 20.03945208 | 1.068171978 | 66 | 508 | SUCCESS | TRUE | 2025/11/5 21:50 | 769f6f0f-943b-4ef1-a265-6434339c42ab |

Each row represents one LLM judgment, with `Think` reasoning traces.<br>

You can visualize or summarize results using tidyverse tools, for instance:<br>

```r
library(dplyr)
summary_res <- res %>%
  group_by(Condition) %>%
  summarise(
    mean_FTL    = mean(FirstTokenLatency, na.rm = TRUE),
    mean_RT     = mean(TotalResponseTime, na.rm = TRUE),
    mean_tokens = mean(CompletionTokens, na.rm = TRUE),
    Y_prob      = mean(Response == "Y", na.rm = TRUE)  # Probability of responding "Y"
  )

print(summary_res)
```
you will get something like this:<br>
| Condition   | mean_FTL | mean_RT | mean_tokens | Y_prob |
|------------|----------|--------|------------|-------|
| Anomalous  | 1.06     | 21.9   | 552        | 0     |
| Control    | 0.965    | 10.7   | 257        | 1     |
| GardenPath | 0.914    | 21.1   | 534        | 0.25  |

and plot it:

```r
library(dplyr)
library(ggplot2)
library(scales)
plot_bar <- function(data, y_var, y_label, title) {
  ggplot(data, aes(x = Condition, y = !!sym(y_var), fill = Condition)) +
    geom_col(width = 0.6, color = "black") +
    labs(title = title,
         x = "Condition",
         y = y_label) +
    theme_minimal(base_size = 14) +
    theme(legend.position = "none",
          plot.title = element_text(hjust = 0.5, face = "bold"))
}

# 1. Total Response Time
plot_bar(summary_res, "mean_RT", "Mean Total Response Time (s)", 
         "Mean Total Response Time by Condition")

# 2. First Token Latency
plot_bar(summary_res, "mean_FTL", "Mean First Token Latency (s)", 
         "Mean First Token Latency by Condition")

# 3. Completion Tokens
plot_bar(summary_res, "mean_tokens", "Mean Completion Tokens", 
         "Mean Completion Tokens by Condition")

# 4. Probability of responding "Y"
ggplot(summary_res, aes(x = Condition, y = Y_prob, group = 1)) +
  geom_line(color = "#2c7fb8", size = 1.2) +
  geom_point(size = 3, color = "#2c7fb8") +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  labs(title = "Probability of Responding 'Y' by Condition",
       x = "Condition",
       y = "Probability of 'Y'") +
  theme_minimal(base_size = 14) +
  theme(plot.title = element_text(hjust = 0.5, face = "bold"))
```

<img width="738" height="502" alt="image" src="https://github.com/user-attachments/assets/e7ce62f3-bb64-47f3-b722-6190995f1c3b" />
<img width="738" height="502" alt="image" src="https://github.com/user-attachments/assets/692275f8-051f-4710-bfc1-78d9ede40ecb" />
<img width="738" height="502" alt="image" src="https://github.com/user-attachments/assets/25c55a6b-2891-4a26-bd64-872622d5bd00" />
<img width="738" height="502" alt="image" src="https://github.com/user-attachments/assets/973adcae-2af3-4bd7-96d9-6c1a477d1a15" />


🧠 **Interpretation**

This experiment demonstrates how PsyLingLLM can replicate classic psycholinguistic paradigms, allowing quantitative comparison of LLM behavior across syntactic and semantic manipulations.<br>

In reasoning models, the results show human-like processing patterns: `GardenPath` and `Anomalous` sentences take **longer** to process and generate **more tokens** than Control sentences. Acceptance judgments correspond with sentence type: `Control` sentences are always accepted, `GardenPath` sentences are partially (25%) accepted, and `Anomalous` sentences are never accepted.<br>


>_Note_: This is a methodological demonstration. Due to the limited number of trials, these results do not constitute a full statistical analysis.<br>


   > _References_:
   > Ferreira, F., & Henderson, J. M. (1991). Recovery from misanalyses of garden-path sentences. Journal of Memory and Language, 30(6), 725–745.
   > Christianson, K., Hollingworth, A., Halliwell, J. F., & Ferreira, F. (2001). Thematic roles assigned along the garden path linger. Cognitive Psychology, 42(4), 368–407.

---

## 3. Sentence Completion Task
This example demonstrates how to run a repeated-trial experiment where each stimulus is presented under multiple experimental conditions.
Unlike single-trial experiments, the input data must include Item or Condition columns to allow proper replication and analysis.

Load preset linguistic material shipped with the package:
```r
path <- system.file("extdata", "Sentence_Completion_Constraint.csv", package = "PsyLingLLM")
```
| Item | Condition_Constraint     | Condition_language | Material                                         |
| ---- | -------------- | ---------- | ------------------------------------------------ |
| 1    | HighConstraint | English    | John went to the bakery to buy a \_\_\_.     |
| 1    | HighConstraint | Chinese    | 小军去面包店买了一个\_\_\_。                              |
| 2    | LowConstraint  | English    | Mary looked out the window and saw a \_\_\_. |
| 2    | LowConstraint  | Chinese    | 小丽望向窗外，看见了一个\_\_\_。                            |

**Running the Experiment**
```r
result <- repeat_trial_experiment(
  data = path,
  repeats = 5,
  api_key = api_key,
  model = model,
  api_url = api_url,
  trial_prompt = "Complete the sentence below by filling in the blank (_____) in the most natural way.
                  Return the full completed sentence only.
                  Do not add any extra text.",
  max_tokens = 1024,
  enable_thinking = TRUE
)
```

**Inspecting the Results**

print(result$Response)
<img width="1449" height="339" alt="image" src="https://github.com/user-attachments/assets/5759d95c-5a94-47c8-922e-3bfceab0c68f" />

Outputs in experiment_results.csv:

<img width="2475" height="648" alt="image" src="https://github.com/user-attachments/assets/01c8a328-ae4c-425f-8da1-375c5a347a13" />


---
## 4. Factorial Designs
This example demonstrates a 2 × 2 factorial design manipulating:
Each trial uses a **Carrier Sentence** with a placeholder `{AUX}`, which is automatically
filled by the `fill_grammar` function according to the experimental condition:

- **Grammaticality**: Determines whether the auxiliary verb is grammatically correct.
- Grammatical → "are"
- Ungrammatical → "is"
- **Tense**: Adjusts the auxiliary verb for past tense.
- Present → keep "are"/"is"
- Past → convert to "were"/"was"


**Step 1. Prepare carrier sentences (stimulus templates)**
>These are carrier sentences with a placeholder {OBJ}.
>Templates help control the context while manipulating only the critical word, ensuring effects can be attributed to the intended factors automaticly.
>
```r
    # Carrier sentences with placeholders
    items <- data.frame(
      Material = c(
        "The children {AUX} playing in the garden.",
        "The dogs {AUX} chasing the cat in the yard."
      ),
      stringsAsFactors = FALSE
    )
```

**Step 2. Define factors (crossed design)**
>A 2 × 2 factorial design: Congruity × Animacy.<br>
>This allows testing main effects and interactions. It should be defined in a list named `factors`.<br>
>
```r
    factors <- list(
      Grammaticality = c("Grammatical", "Ungrammatical"),
      Tense = c("Present", "Past")
    )
```

**Step 3. Trial Prompt (Task Instructions)**

```r
trial_prompt <- "Is the following sentence grammatically correct? (Yes / No)"
```


**Step 4. Define a Fill Function**<br>
>PsyLingLLM allow user to input their own function to tell `factorial_trial_experiment` how to fill their cw into the carrier sentences.<br>
```r
fill_grammar <- function(cond, Carrier_Sentence) {
  # cond[1] = Grammaticality, cond[2] = Tense
  aux <- if (cond[1] == "Grammatical") "are" else "is"
  if (cond[2] == "Past") {
    aux <- if (aux == "are") "were" else "was"
  }
  gsub("\\{AUX\\}", aux, Carrier_Sentence)
}
```
>Grammaticality: chooses a grammatical (“are”) or ungrammatical (“is”) auxiliary.<br>
>Tense: shifts auxiliaries into past tense (“were” / “was”).<br>
>This operationalizes the factorial manipulation: different auxiliary verbs represent different conditions.
>


**Step 5. Run Factorial Experiment**
```r
results <- factorial_trial_experiment(
  data = data,
  factors = factors,
  condition_words = CW,
  fill_function = fill_semantic,
  trial_prompt = trial_prompt,
  api_key = api_key,
  model = model,
  api_url = api_url,
  random = TRUE,
  repeats = 1,
  enable_thinking = TRUE
)
```
>`factorial_trial_experiment()` automatically expands all Item × Condition combinations.<br>
>Each sentence is generated by `fill_grammar()` and paired with the task prompt.
>

**Experiment Output**

<img width="1437" height="87" alt="image" src="https://github.com/user-attachments/assets/6c60df16-c308-457c-baf9-1c1c0e786ef1" />
<img width="2013" height="351" alt="image" src="https://github.com/user-attachments/assets/3dbaf657-6254-49aa-8f26-c90adb4c1ad9" />


---
# 5. Conversation-style Experiment

This example demonstrates how to run a **conversation-style experiment** using `conversation_experiment()`,  
where each trial is appended to the **conversation history** and the model's  
responses are conditioned on **all previous trials**.  

This setup mimics a **web-based LLM interface**, where participants  
see sequential questions and the conversation flows naturally.

> Unlike trial-based experiments (e.g., grammaticality judgments),  
> this design introduces **memory effects**: the model “remembers” prior trials.  
>  
> This allows researchers to study phenomena such as:  
> - **Priming** (e.g., does exposure to correct grammar influence later judgments?)  
> - **Fatigue or adaptation** (e.g., does accuracy drift over multiple trials?)  
> - **Sequential dependencies** (e.g., consistency of responses across context)  

---

### Prepare the data

```r
data <- data.frame(
  TrialPrompt = c(
    "Welcome! Let's start. Please read the following sentence carefully.",
    "Now, consider this sentence:",
    "Finally, evaluate this sentence:"
  ),
  Material = c(
    "The cat is sleeping on the mat.",
    "The children are playing in the park.",
    "The dogs was barking loudly." # intentionally ungrammatical
  ),
  stringsAsFactors = FALSE
)

```
**Run the conversation experiment**
```r
results <- conversation_experiment(
  data = data,
  repeats = 1,
  random = FALSE,
  api_key = api_key,
  model = model,
  api_url = api_url,
  system_prompt = "You are a participant in a psychology experiment.",
  max_tokens = 1024,
  enable_thinking = TRUE,
  output_path = "conversation_results.csv"
)
```
**Experiment Output**
<img width="1428" height="75" alt="image" src="https://github.com/user-attachments/assets/1ca1cb06-2abf-4953-a05b-c4eda45c1ccb" />

<img width="2129" height="411" alt="image" src="https://github.com/user-attachments/assets/bdb18697-95f1-43af-af40-9d194dec1f96" />


>The output looks like a trial experiment,<br>
>except that each trial prompt now includes the entire conversation history.<br>
>
>**Example Conversation Context**
>
> Second trial prompt input

```json
  {"role":"system","content":"You are a participant in a psychology experiment."},
  {"role":"user","content":"Welcome! Let's start. Please read the following sentence carefully.\nThe cat is sleeping on the mat."},
  {"role":"assistant","content":"Sure, I’ve read it. **“The cat is sleeping on the mat.”** Is there anything specific you’d like me to do with this sentence—comment on it, answer a question about it, or something else?"}
```

> Third trial prompt input<br>


```json
  {"role":"system","content":"You are a participant in a psychology experiment."},
  {"role":"user","content":"Welcome! Let's start. Please read the following sentence carefully.\nThe cat is sleeping on the mat."},
  {"role":"assistant","content":"Sure, I’ve read it. **“The cat is sleeping on the mat.”** Is there anything specific you’d like me to do with this sentence—comment on it, answer a question about it, or something else?"},
  {"role":"user","content":"Now, consider this sentence:\nThe children are playing in the park."},
  {"role":"assistant","content":"Got it! I’ve read the sentence: **“The children are playing in the park.”** Is there something specific you’d like me to do with it—analyze it, compare it to the first sentence, or something else?"}
```

---

# 6. Conversation Experiment with Feedback

This example demonstrates a **conversation-style experiment with dynamic feedback**  
using `conversation_experiment_with_feedback()`.  

In this task, the model must judge whether a number is **prime**.  
Difficulty is adjusted adaptively based on performance:

- If the model answers **correctly**, the next trial presents a **larger number**.  
- If the model answers **incorrectly**, the next trial presents a **smaller number**.  

The number is always kept within the range **[2, 200]**, starting from **11**.

### Prepare the initial data

```r
my_data <- data.frame(
  TrialPrompt = c("Is the following number a prime? 11"),
  Material = c(""),
  stringsAsFactors = FALSE
)
```

### Prime checking function
```r
is_prime <- function(n) {
  if (n < 2) return(FALSE)
  if (n == 2) return(TRUE)
  if (n %% 2 == 0) return(FALSE)
  for (i in seq(3, floor(sqrt(n)), by = 2)) {
    if (n %% i == 0) return(FALSE)
  }
  return(TRUE)
}

```

### Feedback function
```r
prime_feedback_fn <- function(response, row, history) {
  # Extract number from the TrialPrompt
  num <- as.integer(stringr::str_extract(row$TrialPrompt, "\\d+"))
  if (is.na(num)) return(NULL)

  # Ground-truth
  correct <- is_prime(num)

  # Parse model's answer (robust matching)
  model_says_prime <- grepl("prime", response, ignore.case = TRUE)
  model_says_not   <- grepl("not.*prime|non-prime", response, ignore.case = TRUE)

  is_correct <- (correct && model_says_prime) || (!correct && model_says_not)

  # Difficulty adjustment
  if (is_correct) {
    step <- sample(5:15, 1)    # harder → larger number
  } else {
    step <- sample(-10:-2, 1)  # easier → smaller number
  }

  next_num <- max(2, min(200, num + step))

  # Next trial
  next_prompt <- paste0("Is the following number a prime? ", next_num)

  return(list(
    next_prompt   = next_prompt,
    next_material = "",   # required for some implementations
    meta = list(
      num = num,
      correct = correct,
      model_says_prime = model_says_prime,
      is_correct = is_correct,
      next_num = next_num
    ),
    name = ifelse(is_correct, "correct→harder", "wrong→easier")
  ))
}

```
### Run the adaptive conversation experiment
```r
res <- conversation_experiment_with_feedback(
  data = my_data,
  api_key = api_key,
  model = model,
  api_url = api_url,
  feedback_fn = prime_feedback_fn,
  apply_mode = "insert_dynamic",  # dynamically insert new trials
  max_trials = 10,                # stop after 10 trials
  delay = 1                       # 1 sec delay between calls
)
```

### Output
This design mimics adaptive testing paradigms in psychology,
where difficulty is adjusted dynamically according to participant performance.
<img width="2246" height="924" alt="image" src="https://github.com/user-attachments/assets/93195edc-78ef-4854-878e-9580024ea237" />

---
# 7. Multi-Model Experiment

This example demonstrates how to run the **same experiment across multiple models**  
using `multi_model_experiment()`.  

This function automates **batch comparison** by looping over a list of models (from a CSV/XLSX file)  
and applying a chosen experiment function (e.g., `trial_experiment`).  

---

**Prepare the model list**

The model file (`Model.xlsx`) must contain at least the following columns:

| Model       | API_URL                   | API_Key      | Enable_Thinking      |
|-------------|---------------------------|--------------|----------------------|
| gpt-4o-mini | https://api.openai.com/v1 | OPENAI_KEY   | TRUE                 |
| llama-3-70b | http://localhost:1234/v1  | LOCAL_KEY    | TRUE                 |

> Additional metadata columns (e.g., Temperature, Notes) can also be included.

---

**Run the multi-model experiment**

```r
results <- multi_model_experiment(
  data = system.file("extdata", "garden_path_sentences.csv", package = "PsyLingLLM"),
  model_file = "Model.xlsx",
  experiment_fn = trial_experiment,
  max_tokens = 1024,
  delay = 0
)
```

**Multi-Model Experiment Output**

>When you run multi_model_experiment(), the results are organized both per model and collectively:
><img width="1113" height="114" alt="image" src="https://github.com/user-attachments/assets/33ea340a-b091-4330-842c-9bb2bf9aba77" />

>**Per-Model Results**
>Each model’s trial results are saved in its own subfolder under the main output directory.
>Files include:
>experiment_results.csv or .xlsx — containing all trials for that model

>**Aggregate Results**
>A single summary file (e.g., MultiModel_Results) collects all models’ outputs in one table.
>Useful for direct comparison across models.
>The same columns are included as above, plus a ModelName column to distinguish models.

<img width="1719" height="288" alt="image" src="https://github.com/user-attachments/assets/65d44bef-73e8-4a23-916c-e27aa5ba8d6b" />
<img width="2163" height="489" alt="image" src="https://github.com/user-attachments/assets/8e6f610e-ab98-4bc1-b391-e7841216f5f2" />

---
...


Experiment system
```
├── R/
│ ├── llm_caller.R
│ ├── trial_experiment.R
│ ├── factorial_trial_experiment.R
│ ├── conversation_experiment.R
│ ├── conversation_experiment_with_feedback.R
│ ├── multi_model.R
│ ├── save_results.R
│ ├── generate_experiment_materials.R
│ ├── generate_factorial_experiment_list.R
│ ├── get_model_config.R
│ └── get_registry_entry.R
├── inst/
│   └── extdata/
│       ├── Garden_path_sentences.csv
│       └── Sentence_Completion.csv
```

Register system
```
├── R/
│ ├── register_orchestrator.R                  # llm_register(): end-to-end analysis → registry
│ ├── register_probe_request.R                 # probe_llm_streaming(): POST (non-stream & SSE)
│ ├── register_rank_endpoint.R                 # scoring (NS & ST) and keyword lexicon
│ ├── register_build_input.R                   # build_standardized_input(), Pass-2 templates
│ ├── register_read.R                          # structural inference & path helpers
│ ├── register_classify.R                      # URL → interface classification
│ ├── register_entry.R                         # build_registry_entry_from_analysis()
│ ├── register_io.R                            # upsert into ~/.psylingllm/model_registry.yaml
│ ├── register_preview.R                       # CI/human-readable preview
│ ├── register_validate.R                      # Pass-2 consistency report
│ └── register_utils.R                         # helpers (internal-only)
├── inst/
│   └── registry/
│       └── system_registry.yaml               # default registry file (pre-regist)
```

Utils
```
├── R/
│ ├── json_utils.R
│ ├── progress_bar.R
│ ├── write_experiment_log.R
│ ├── error_handling.R
│ ├── llm_parser.R
│ └── schema.R

```
