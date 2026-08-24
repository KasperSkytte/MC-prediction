# Required pkgs are assumed to be already installed in a container
# Check if running inside a container (Docker or Apptainer)
in_docker <- file.exists("/.dockerenv")
in_apptainer <- nzchar(Sys.getenv("APPTAINER_CONTAINER")) || 
                nzchar(Sys.getenv("SINGULARITY_CONTAINER"))

# Only source renv if not in a container
if (!in_docker && !in_apptainer) {
  source("renv/activate.R")
}

# Load languageserver only when running inside VS Code, regardless of containerization
is_vscode_session <- nzchar(Sys.getenv("VSCODE_GIT_IPC_HANDLE")) ||
  Sys.getenv("TERM_PROGRAM") == "vscode" ||
  nzchar(Sys.getenv("VSCODE_CWD")) ||
  nzchar(Sys.getenv("VSCODE_PID"))

if (is_vscode_session && requireNamespace("languageserver", quietly = TRUE)) {
  require("languageserver")
}
