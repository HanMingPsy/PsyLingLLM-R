**PsyLingLLM** is an experimental toolkit for studying **human-like language processing** with Large Language Models (LLMs) in **R**.  
It provides functions to **design, execute, and analyze** psycholinguistic, psychological, and educational experiments using LLMs.

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

Clone the repository and install locally:

```r
# Install devtools if not available
install.packages("devtools")

# Install from GitHub
devtools::install_github("HanMingPsy/PsyLingLLM-R")
```


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

---


# 📑 Table of Contents

- [1. Single-Trial Experiment](#1-single-trial-experiment)
- [2. Repeated Trials with Conditions](#2-garden-path-sentences-judgment-task)
- [3. Factorial Designs](#4-factorial-designs)
- [4. Conversation-based Experiments](#5-conversation-style-experiment)
- [5. Dynamic Feedback & Adaptive Difficulty](#6-conversation-experiment-with-feedback)
- [6. Multi-Model Comparisons](#7-multi-model-experiment)
- [7. Data Handling (CSV/XLSX, UTF-8 Safe)](#7-data-handling-csvxlsx-utf-8-safe)



# Prat 1 Experiment System
---
# 🚀 Quick Start
### 🔑 Authentication and Model Setup

To run any experiment, you need to prepare the following three items **from your LLM provider**:

1. **API Key** – your personal access token (e.g., from `OpenAI`).  
2. **Model Name** – the identifier of the model you want to call (e.g., `"gpt-4"`).  
3. **API URL (Endpoint)** – the HTTP endpoint for chat/completion requests   
   (e.g., OpenAI-compatible: `https://api.openai.com/v1/chat/completions`).

### How to find them?
- **API Key**: usually available in your provider’s user dashboard under *API Keys* or *Access Tokens*.  
- **Model Name**: check your provider’s *Models* or *Playground* page; names are case-sensitive.  
- **API URL**: check the developer documentation of your provider. Many are OpenAI-compatible (`/v1/chat/completions`).

⚠️ **Important**: Do not commit your API key to public. 

**Use environment variables**

```r
Sys.setenv(API_KEY = "your_api_key_here")

Sys.setenv(MODEL_NAME = "your_model_here")
Sys.setenv(API_URL = "https://your_api_url_here")
```
or 

**Directly input inside PsyLingLLM experiment functions**
```
result <- trial_experiment(
  data   = "Demo/Materials_for_Demo/garden_path_sentences.csv",
  api_key = "your_api_key_here",
  model   = "your_model_here",
  api_url = "https://your_api_url_here"
)
```
---

## 1. Single-Trial Experiment

```r
library(PsyLingLLM)
df <- data.frame(
  Material = c("The cat sat on the ____.", 
               "这只猫咪坐在____上。")
)

result <- trial_experiment(
  data = df,
  api_key = "your_api_key_here",
  model   = "your_model_here",
  api_url = "https://your_api_url_here",
  trial_prompt = "Please complete the blank in the sentence."
)

print(result$Response)
```
---

### ✅ Example Output Explanation

When you run an experiment with `PsyLingLLM`, you may see console output like:

<img width="1350" height="207" alt="image" src="https://github.com/user-attachments/assets/fcc48d1b-2d45-4f1d-bc17-b8c893407c51" />



**Explanation:**

- `[█████...] 100%` → Progress bar showing the completion of all trials.
- `Trial 1/2` → Indicates the current trial number out of total trials.
- `ETA: 00:04` → Estimated time remaining (s).
- `- tencent/Hunyuan-A13B-Instruct` → The model used for this experiment.

When experiment is finished you will see:
- `completed! Total elapsed: 10 secs` → The experiment finished and took 10 seconds in total.
<img width="1380" height="81" alt="image" src="https://github.com/user-attachments/assets/680191e5-bd92-4e71-81ad-0914e8b25472" />


After this, the experiment results will be saved to your specified `output_path` or the default path `~/PsyLingLLM_Results`, and you can inspect the model responses in your `data.frame`.


### 📝 Example Experiment Output

After running a trial experiment with `PsyLingLLM`, the results are returned as a `data.frame` (or saved to CSV/XLSX) like this:

| Run | Item | TrialPrompt | Material | Response | Think | ModelName | ResponseTime |
|-----|------|-------------|---------|---------|------|-----------|--------------|
| 1 | 1 | Please complete the blank in the sentence: | The cat sat on the ____ | The cat sat on the couch. | "Okay, let's see. The user wants me to fill in the blank..." | tencent/Hunyuan-A13B-Instruct | 9.06 |
| 2 | 2 | Please complete the blank in the sentence: | 猫咪坐在____上。 | 椅子 | "Okay, let's see. The user wants me to fill in the blank..." | tencent/Hunyuan-A13B-Instruct | 4.18 |

**Column Explanations:**

- **Run** → The overall trial number.  
- **Item** → The number of item or stimulus provided by user.  
- **TrialPrompt** → The instruction or prompt given to the model.  
- **Material** → The sentence or context the model is responding to.  
- **Response** → The final answer generated by the model.  
- **Think** → The model’s reasoning process (only if model support at), which is especially useful for psycholinguistic analysis or debugging prompts.  
- **ModelName** → The LLM model used for this trial.  
- **ResponseTime** → Time in seconds taken by the model to generate the response.

---


### ⚙️ Function Arguments: `trial_experiment()`

- **`data`** → The experiment materials. Can be a `data.frame` or a CSV/XLSX file.  
   >The data argument specifies the experimental materials. 
   It supports multiple input formats and follows a clear processing pipeline `generate_llm_experiment_list()` to ensure compatibility and reproducibility.
   >
   >**Input Formats**
   >
   > `PsyLingLLM` will automatically detect whether your data input is:
   >
   >`CSV file (.csv)`
   >Read with readr::read_csv()
   >
   >Automatically checks for non-UTF8 characters. If found, they are auto-converted to UTF-8 using stringi::stri_enc_toutf8(), and a warning is shown.If issues persist → save as `XLSX` instead of CSV.
   >
   >`Excel file (.xls, .xlsx)`
   >Read with readxl::read_excel()
   >Recommended for Chinese or other non-ASCII text, since Excel avoids common CSV encoding issues.
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
  >If missing from your data, the system will automatically add these columns:<br>
  >`Item` Sequential item number assigned to each row<br>
  >`Run` Trial index after repetitions and randomization<br>
  >`TrialPrompt` Global prompt applied to trials (if not provided per row)<br>
  >
  >**Optional Columns**<br>
  > `Condition` One or more experimental condition columns (e.g., Congruity)<br>
  > `Target` Correct answer or expected response<br>
  > `CorrectResponse` Another variant for expected response<br>
  > `TrialType` Type of trial, if multiple trial types are used<br>
  > `Metadata` Any additional metadata you want to store per trial
  >
- **`repeats`** → The repeats parameter controls how many times the entire experiment dataset (all rows in data) should be duplicated.
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
  > | Item | Material    |
  > | ---- | ----------- |
  > | 1    | Sentence 1  |
  > | 2    | Sentence 2  |
  > | …    | …           |
  > | 10   | Sentence 10 |
  > | 1    | Sentence 1  |
  > | 2    | Sentence 2  |
  > | …    | …           |
  > | 10   | Sentence 10 |
  > | 1    | Sentence 1  |
  > | …    | …           |
  > | 10   | Sentence 10 |
   >
   >df_expanded <- df[rep(seq_len(nrow(df)), 3), , drop = FALSE]
   >
- **`random`** → Whether to shuffle the order of trials (`TRUE`) or keep them sequential (`FALSE`).  

- **`api_key`**, **`model`**, **`api_url`** → The credentials and endpoint of your LLM provider.  

- **`system_prompt`** → A global instruction given to the model at the start.  
   >The `system_prompt` parameter allows you to set the **behavior, role, and style** of the large language model (LLM) for your experiment.  
   >It is sent as the **first system message** in the conversation, providing the model with instructions on how to act.
   >
   >**How it works**<br>
   > Placed at the beginning of the message sequence:<br>
   ```r
         messages <- list(
           list(role = "system", content = system_prompt),
           list(role = "user", content = trial_prompt)
         )
   ```
  >**Examples:**<br>
  > `"You are a participant in a psychology experiment."` (default)  
  > `"You are a child learning English."` (simulate a learner)  
  > `"You are a bilingual speaker."` (simulate bilingual processing)  
  >
  >Researchers can use `system_prompt` to:<br>
  > Standardize responses across trials  
  > Manipulate the experimental context  
  > Create conditions that test different cognitive or linguistic scenarios  
  >
- **`role_mapping`** → Defines how roles are labeled (Check your API).  
   >The role_mapping parameter tells LLM how to translate between internal role names and the role labels required by your LLM API.<br>
   >By default, PsyLingLLM assumes the OpenAI convention:<br>
   ```r
         role_mapping = list( 
           user = "user", 
           system = "system",
           assistant = "assistant"
         )
   ```
   >`system` → Provides the global instruction or context for the model
   >`user` → Represents the trial prompt or experimental stimulus.
   >`assistant` → Represents the model's reply (the generated output).
   >
   >Example 1 – Anthropic Claude. Claude uses "human" instead of "user", and "assistant" stays the same:
   ```r
         role_mapping = list(
           user = "human",
           system = "system",
           assistant = "assistant"
         )
   ```
   >**Why this matters**
   >If role_mapping does not match your provider’s expected labels, your request may fail or the model may ignore parts of the prompt.
   >Always check your provider’s API documentation for the correct role labels, and adjust role_mapping accordingly.

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

- **`temperature`** → Controls randomness of the response (Check your API).  
   >The temperature parameter controls the randomness (or creativity) of the model’s output.
   >It affects how likely the model is to pick less probable words during text generation.
   >
   >**How it works**<br>
   >Low values **(e.g., 0 – 0.3)**
   >Output is more deterministic, stable, and focused.
   >The model will almost always choose the most likely completion.
   >Useful for tasks requiring accuracy and consistency, e.g., grammar correction, factual Q&A, psycholinguistic experiments where variability is undesirable.
   >
   >Medium values **(e.g., 0.5 – 0.7, default = 0.7)**
   >Output is balanced: reasonably creative but not too random.
   >Suitable for most experimental stimuli generation and general-purpose experiments.
   >
   >High values **(e.g., 0.8 – 1.2)**
   >Output becomes more diverse and creative, but also less predictable.
   >Useful for tasks like brainstorming, generating multiple varied responses, or simulating human-like variability in language experiments.
   >
   >Extreme values **(> 1.2)**
   >Output may become very random or even incoherent.
   >Rarely useful in controlled experiments.
   >
- **`enable_thinking`** → If `TRUE`, captures the model’s reasoning process (chain-of-thought).  
  >This is saved into the **Think** column for later analysis.<br>
  >Setting enable_thinking = FALSE does not stop the model from thinking internally; it switches the LLM to a fast mode that produces answers with minimal or hidden reasoning.
   >**How it works**<br>
   >PsyLingLLM adapts API calls for different models, such as:
   >GPT series	reasoning_effort = "low" (less explicit CoT)
   >Hunyuan	enable_thinking = FALSE (fast mode)
   >
   >**Post-parsing logic**:<br>
   >If `reasoning_content` exists, it is extracted as `Think` based on API rules.<br>
   >If `Think` content goes into Response:<br>
   >Keyword extraction: Detects phrases like Reasoning:, Note:, 解析:, 思考: to capture hidden reasoning.
   >Bracketed annotations: Extracts reasoning in parentheses or brackets following sentences.
   >
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
