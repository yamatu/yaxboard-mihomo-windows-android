use crate::service::hub::run_service;

use std::env;
use std::ffi::OsString;

use std::time::Duration;

use tokio::runtime::Runtime;

use windows_service::{
    define_windows_service,
    service::{
        ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus,
        ServiceType,
    },
    service_control_handler::{self, ServiceControlHandlerResult},
    service_dispatcher, Result,
};

const SERVICE_NAME: &str = "FlClashHelperService";

const SERVICE_TYPE: ServiceType = ServiceType::OWN_PROCESS;

pub fn main() -> Result<()> {
    match parse_mode(env::args().skip(1)) {
        RunMode::Help => {
            print_help();
            Ok(())
        }
        RunMode::Console => run_console(),
        RunMode::Service => match start_service() {
            Ok(()) => Ok(()),
            Err(err) => {
                // 当用户在命令行直接运行服务程序时，windows-service 会返回 1063：
                // “服务进程无法连接到服务控制器上”。这是预期行为（该程序应由 SCM 启动）。
                // 为了避免误判为“程序坏了”，这里给出更清晰的提示。
                if is_not_started_by_scm(&err) {
                    eprintln!(
                        "{}\n\n{}",
                        "错误：检测到你在命令行直接运行了 Windows 服务程序，因此无法连接到服务控制器（错误码 1063）。",
                        help_text()
                    );
                    Ok(())
                } else {
                    Err(err)
                }
            }
        },
    }
}

pub fn start_service() -> Result<()> {
    service_dispatcher::start(SERVICE_NAME, service_entry)
}

define_windows_service!(service_entry, service_main);

pub fn service_main(_arguments: Vec<OsString>) {
    if let Ok(rt) = Runtime::new() {
        rt.block_on(async {
            let _ = run_windows_service().await;
        });
    }
}
async fn run_windows_service() -> anyhow::Result<()> {
    let status_handle = service_control_handler::register(
        SERVICE_NAME,
        move |event| -> ServiceControlHandlerResult {
            match event {
                ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
                ServiceControl::Stop => std::process::exit(0),
                _ => ServiceControlHandlerResult::NotImplemented,
            }
        },
    )?;

    status_handle.set_service_status(ServiceStatus {
        service_type: SERVICE_TYPE,
        current_state: ServiceState::Running,
        controls_accepted: ServiceControlAccept::STOP,
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 0,
        wait_hint: Duration::default(),
        process_id: None,
    })?;

    run_service().await
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RunMode {
    /// 输出帮助并退出
    Help,
    /// 以普通控制台程序运行（用于调试）
    Console,
    /// 以 Windows 服务方式启动（默认）
    Service,
}

fn parse_mode(args: impl Iterator<Item = String>) -> RunMode {
    // 这里不引入 clap 等依赖，保持 helper 体积小且启动快。
    // 注意：该程序在默认模式下应由 Windows SCM 启动；手动运行会报 1063。
    for arg in args {
        match arg.as_str() {
            "-h" | "--help" | "/?" => return RunMode::Help,
            "--console" => return RunMode::Console,
            _ => {}
        }
    }
    RunMode::Service
}

fn run_console() -> Result<()> {
    print_help();
    if let Ok(rt) = Runtime::new() {
        rt.block_on(async {
            let _ = run_service().await;
        });
    }
    Ok(())
}

fn is_not_started_by_scm(err: &windows_service::Error) -> bool {
    // windows-service 的错误类型在不同版本/特性下可能不便于做结构化匹配；
    // 这里使用字符串兜底，只针对常见的 1063 情况做友好提示。
    // 示例：Winapi(Os { code: 1063, kind: Uncategorized, message: "服务进程无法连接到服务控制器上。" })
    err.to_string().contains("1063")
}

fn help_text() -> &'static str {
    "FlClashHelperService 用法：\n\
  - 该程序是 Windows 服务，正常情况下不需要手动运行。\n\
  - 由 FlClash / XBoard-Mihomo 在需要管理员权限时自动注册并启动。\n\
\n\
调试模式（不通过 SCM，直接在命令行运行）：\n\
  FlClashHelperService.exe --console\n\
\n\
手动管理服务（需要管理员权限）：\n\
  sc query FlClashHelperService\n\
  sc start FlClashHelperService\n\
  sc stop FlClashHelperService\n\
  sc delete FlClashHelperService\n"
}

fn print_help() {
    println!("{}", help_text());
}




