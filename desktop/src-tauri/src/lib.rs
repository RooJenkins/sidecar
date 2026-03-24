use std::process::Command as StdCommand;
use std::path::PathBuf;

fn find_cli_js() -> PathBuf {
    // 1. Check SIDECAR_CLI_PATH env var
    if let Ok(path) = std::env::var("SIDECAR_CLI_PATH") {
        let p = PathBuf::from(&path);
        if p.exists() {
            return p;
        }
    }

    // 2. Walk up from executable to find dist/cli.js (dev mode)
    if let Ok(exe) = std::env::current_exe() {
        for ancestor in exe.ancestors() {
            let candidate = ancestor.join("dist").join("cli.js");
            if candidate.exists() {
                return candidate;
            }
            // Also check parent's parent (for src-tauri/target/debug/)
            let candidate2 = ancestor.join("..").join("..").join("..").join("dist").join("cli.js");
            if let Ok(resolved) = candidate2.canonicalize() {
                if resolved.exists() {
                    return resolved;
                }
            }
        }
    }

    // 3. Check relative to CWD
    let cwd_candidate = PathBuf::from("dist/cli.js");
    if cwd_candidate.exists() {
        return cwd_candidate;
    }

    // 4. Fallback — assume globally installed sidecar
    PathBuf::from("sidecar")
}

#[tauri::command]
fn run_sidecar(args: Vec<String>) -> Result<String, String> {
    let cli_path = find_cli_js();

    let (program, mut cmd_args) = if cli_path.extension().map_or(false, |ext| ext == "js") {
        // JS file — run with node
        ("node".to_string(), vec![cli_path.to_string_lossy().to_string()])
    } else {
        // Binary — run directly
        (cli_path.to_string_lossy().to_string(), vec![])
    };

    cmd_args.extend(args);

    let output = StdCommand::new(&program)
        .args(&cmd_args)
        .output()
        .map_err(|e| format!("Failed to spawn {}: {}", program, e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Exit code {}: {}", output.status.code().unwrap_or(-1), stderr));
    }

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![run_sidecar])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
