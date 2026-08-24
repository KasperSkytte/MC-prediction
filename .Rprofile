# Required pkgs are assumed to be already installed in the "mc-prediction" conda env

# Load languageserver only when running inside VS Code
is_vscode_session <- nzchar(Sys.getenv("VSCODE_GIT_IPC_HANDLE")) ||
  Sys.getenv("TERM_PROGRAM") == "vscode" ||
  nzchar(Sys.getenv("VSCODE_CWD")) ||
  nzchar(Sys.getenv("VSCODE_PID"))

if (is_vscode_session && requireNamespace("languageserver", quietly = TRUE)) {
  require("languageserver")
}
