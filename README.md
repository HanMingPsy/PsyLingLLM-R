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

- ✅ **Single-trial collection**  
  Run controlled experiments where the model responds to one stimulus at a time, similar to presenting a single trial in psychology experiments.  

- ✅ **Repetition and randomization**  
  Present the same material multiple times, or shuffle the order of trials, to study consistency and random effects—just like in behavioral experiments with human participants.  

- ✅ **Factorial design support**  
  Test the influence of multiple factors (e.g., congruity × language condition) in a structured way, automatically expanding your stimuli into all combinations.  

- ✅ **Conversation-based tasks**  
  Go beyond single prompts—simulate interactive experiments where the model engages in multi-turn dialogues, keeping track of context.  

- ✅ **Adaptive and feedback-based experiments**  
  Dynamically adjust task difficulty or provide feedback during the session, enabling learning-style or tutoring experiments with LLMs.  

- ✅ **Customizable experimental methods**  
  Beyond predefined setups, researchers can flexibly design their own experimental paradigms.  
  You can control how stimuli are presented, how prompts are structured, and even how the model’s responses are evaluated. 

- ✅ **Multi-model comparisons**  
  Easily run the same experiment across different LLMs, to test how models vary in their “behavior” under identical conditions.  

- ✅ **Robust data handling**  
  Import/export CSV or Excel files with full UTF-8 support, making it straightforward to use materials in English, Chinese, or other languages.  

- ✅ **Unified Registry Management**
Version-controlled YAML files maintain reproducible experiment setups across all model providers and custom endpoints.

- ✅ **Automated Endpoint Configuration**
Intelligent probing automatically detects API schemas, response paths, and streaming protocols—eliminating manual setup for any LLM provider.


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
   > _note_:If stream = TRUE but the selected model does not support streaming, PsyLingLLM will ignore this setting and fall back to non-streaming mode, and FirstTokenLatency will not be available.<br>
   > _note_:`FirstTokenLatency` is only available when `stream = TRUE`.<br>
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
   >_Note_:If your custom mapping does not match the provider’s expected role labels, the request may fail or certain message parts (e.g., `system` or `assistant` prompts) may be ignored by the model.
   >
- **`optionals`** → Optional named list controlling optional parameters for the LLM request (**except** stream).<br>
   >The `optionals` argument allows you to specify **user-provided optional fields** that may be included in the request body if supported by the model registry.<br>
   
   >PsyLingLLM uses a tri-state logic to handle these optionals:
      >**Use registry defaults**	Omit optionals entirely (missing(optionals) → registry defaults are applied).
      >**Disable optional parameters**	optionals = NULL → no optional parameters sent, API uses its own defaults.
      >**Inject specific options**	optionals = list(reasoning = "high") → only reasoning and stream are injected.





- **`max_tokens`** → Maximum length of the model’s response.
   >The `max_tokens` parameter sets the **maximum number of tokens** the model can generate in a single response.  
   >A token roughly corresponds to a word or word piece (e.g., "cat" = 1 token, "running" = 2 tokens: "runn", "ing").  
   >It is an upper bound, not a target length. The model decides when to stop naturally, but if this limit is too low, the output may be cut off mid-sentence. 
   
   >**Why this matters**<br>
   >max_tokens ensures:<br>
   >Responses are bounded → avoids excessively long outputs that may waste time or resources.<br>
   >Experimental control → guarantees each trial produces outputs within a predictable size range.<br>
   >If you need consistent response length (e.g., always one short sentence), use prompt design, not max_tokens.<br>
   >
   >Example prompt:<br>
   >“Please answer in one short sentence of about 10 words.”


- **`delay`** → Pause time (in seconds) between trials.  
   >This is used to control the pacing of API requests.<br>
   >After each trial, the function pauses for `delay` seconds to avoid sending requests too quickly.<br>
   >If the API returns a `429 Too Many Requests` error, an **exponential backoff** is applied:  

   >This ensures that bursts of requests are automatically throttled, reducing the chance of hitting rate limits.<br>
   >Only the final successful response counts toward the recorded `ResponseTime`; the wait during retries is **not** included.

- **`output_path`** → Where to save the results (CSV or XLSX).  
   >Supports both **CSV** and **XLSX** formats.<br>
   >Defaults to `"experiment_results.csv"` if not specified.<br>
   >The function automatically chooses the save method based on the file extension:<br>
   >`.csv` → uses `readr::write_excel_csv()`<br>
   >`.xls` / `.xlsx` → uses `openxlsx::write.xlsx()` (requires the `openxlsx` package)<br> 
   >If an unsupported extension is provided, the function defaults to CSV and appends `.csv` to the filename. <br>
   >After saving, a confirmation message is printed to the console <br>

- **`Return value:`**  
  > The function returns a **`data.frame`** containing all trial results.
---




## 2. Garden Path Sentences Judgment Task
This example demonstrates how to run a repeated-trial experiment using all available parameters in trial_experiment().
It shows how to load demo linguistic materials, configure model behavior, and control experiment pacing.


Load preset linguistic material shipped with the package:
```r
path <- system.file("extdata", "garden_path_sentences.csv", package = "PsyLingLLM")
```
Input Data :

| Item | Condition   | Material                           | TrialPrompt                                                        | Target |
|------|-------------|------------------------------------|--------------------------------------------------------------------|--------|
| 1    | GardenPath  | The old man the boats.             | Read the following sentence and judge whether it is easy to understand (Yes / No) | No     |
| 2    | GardenPath  | The horse raced past the barn fell.| Read the following sentence and judge whether it is easy to understand (Yes / No) | No     |
| 3    | GardenPath  | Fat people eat accumulates.        | Read the following sentence and judge whether it is easy to understand (Yes / No) | No     |
| 4    | GardenPath  | The man whistling tunes pianos.    | Read the following sentence and judge whether it is easy to understand (Yes / No) | No     |
| 5    | Control     | Birds are singing in the garden.   | Read the following sentence and judge whether it is easy to understand (Yes / No) | Yes    |
| 6    | Control     | The children played football after school.| Read the following sentence and judge whether it is easy to understand (Yes / No) | Yes    |

-**Running the Experiment**
```r
result <- trial_experiment(
  data = path,
  api_key = api_key,
  model   = model,
  api_url = api_url,
  random = FALSE,
  repeats  = 2,
  delay = 0, 
  max_tokens = 1024, 
  enable_thinking = TRUE,
  output_path = "experiment_results.csv"
)
```
-**Inspecting the Results**

print(result$Response)

<img width="1389" height="117" alt="image" src="https://github.com/user-attachments/assets/66517938-b199-4ded-9555-4ef045e08c0c" />

You may get outputs like the following in `experiment_results.csv`:

<img width="1785" height="1167" alt="image" src="https://github.com/user-attachments/assets/85ac0915-8f46-43ed-8e50-28a20b37e3c3" />

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
