using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace PortSearcherWin.Core
{
    public record PortInfo(
        ushort Port,
        int Pid,
        string ProcessName,
        string Protocol,
        string Uptime
    );

    public class PortScanner
    {
        private const int ProcessTimeoutMs = 3000;

        public PortScanner() { }

        // netstat -ano 로 현재 사용 중인 포트 목록 가져오기 (동기 버전)
        public List<PortInfo> ActivePorts()
        {
            try
            {
                return ActivePortsAsync().GetAwaiter().GetResult();
            }
            catch
            {
                return new List<PortInfo>();
            }
        }

        // netstat -ano 로 현재 사용 중인 포트 목록 가져오기 (비동기 버전)
        public async Task<List<PortInfo>> ActivePortsAsync(CancellationToken cancellationToken = default)
        {
            var results = new List<PortInfo>();
            
            try
            {
                var startInfo = new ProcessStartInfo
                {
                    FileName = "netstat.exe",
                    Arguments = "-ano",
                    RedirectStandardOutput = true,
                    RedirectStandardError = false,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using var process = new Process { StartInfo = startInfo };
                if (!process.Start()) return results;

                // 비동기로 출력 스트림 읽기 시작
                var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
                
                // 프로세스 종료 혹은 타임아웃 비동기 대기
                var exitTask = process.WaitForExitAsync(cancellationToken);
                var delayTask = Task.Delay(ProcessTimeoutMs, cancellationToken);

                var completedTask = await Task.WhenAny(exitTask, delayTask);
                if (completedTask == delayTask)
                {
                    // 타임아웃 발생 시 강제 종료
                    process.Kill(true);
                    return results;
                }

                string output = await outputTask;
                var lines = output.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);

                foreach (var line in lines)
                {
                    var cleanLine = line.Trim();
                    if (string.IsNullOrEmpty(cleanLine)) continue;
                    if (cleanLine.StartsWith("Proto") || cleanLine.StartsWith("Active")) continue;

                    var parts = cleanLine.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                    if (parts.Length < 4) continue;

                    string proto = parts[0].ToUpper();
                    string localAddress = parts[1];
                    string state = "";
                    string pidStr = "";

                    if (proto == "TCP")
                    {
                        if (parts.Length >= 5)
                        {
                            state = parts[3].ToUpper();
                            pidStr = parts[4];
                        }
                        else
                        {
                            pidStr = parts[3];
                        }
                    }
                    else if (proto == "UDP")
                    {
                        pidStr = parts[3];
                    }
                    else
                    {
                        continue;
                    }

                    // TCP는 LISTENING 상태만 필터링
                    if (proto == "TCP" && state != "LISTENING")
                    {
                        continue;
                    }

                    if (!int.TryParse(pidStr, out int pid)) continue;

                    // 포트 번호 파싱 (예: 127.0.0.1:8080 또는 [::]:8080)
                    ushort port = 0;
                    int colonIndex = localAddress.LastIndexOf(':');
                    if (colonIndex >= 0 && colonIndex < localAddress.Length - 1)
                    {
                        string portStr = localAddress.Substring(colonIndex + 1);
                        ushort.TryParse(portStr, out port);
                    }

                    if (port == 0) continue;

                    if (!results.Any(r => r.Port == port && r.Pid == pid))
                    {
                        var (processName, uptime) = GetProcessInfo(pid);
                        results.Add(new PortInfo(
                            Port: port,
                            Pid: pid,
                            ProcessName: processName,
                            Protocol: proto,
                            Uptime: uptime
                        ));
                    }
                }
            }
            catch (Exception)
            {
                // 실패 시 빈 리스트 반환
            }

            return results.OrderBy(r => r.Port).ToList();
        }

        // 프로세스 정보 (이름, 업타임) 가져오기
        private (string name, string uptime) GetProcessInfo(int pid)
        {
            if (pid == 0) return ("System Idle Process", "");
            if (pid == 4) return ("System", "");

            try
            {
                using var proc = Process.GetProcessById(pid);
                string name = proc.ProcessName;
                string uptime = "";

                try
                {
                    var startTime = proc.StartTime;
                    uptime = FormatUptime(DateTime.Now - startTime);
                }
                catch
                {
                    // 권한 부족 등으로 시작 시간 조회 불가능 시 예외 무시
                }

                return (name, uptime);
            }
            catch
            {
                return ($"Unknown (PID: {pid})", "");
            }
        }

        private string FormatUptime(TimeSpan elapsed)
        {
            if (elapsed.TotalDays >= 1)
            {
                return $"{(int)elapsed.TotalDays}d {elapsed.Hours}h";
            }
            if (elapsed.TotalHours >= 1)
            {
                return $"{elapsed.Hours}h {elapsed.Minutes}m";
            }
            if (elapsed.TotalMinutes >= 1)
            {
                return $"{elapsed.Minutes}m {elapsed.Seconds}s";
            }
            return $"{elapsed.Seconds}s";
        }

        // 포트 바인딩 테스트 (TCP)
        public bool IsPortAvailable(ushort port)
        {
            try
            {
                using var socket = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
                socket.Bind(new IPEndPoint(IPAddress.Any, port));
                return true;
            }
            catch
            {
                return false;
            }
        }

        // 포트 점유 중인 프로세스 조회 (비동기 버전)
        public async Task<PortInfo?> ProcessUsingAsync(ushort port, CancellationToken cancellationToken = default)
        {
            var ports = await ActivePortsAsync(cancellationToken);
            return ports.FirstOrDefault(r => r.Port == port);
        }

        // 포트 점유 중인 프로세스 조회 (동기 버전)
        public PortInfo? ProcessUsing(ushort port)
        {
            return ActivePorts().FirstOrDefault(r => r.Port == port);
        }

        // 프로세스 강제 종료 (비동기 버전)
        public async Task<(bool success, string? errorMessage)> KillProcessAsync(int pid)
        {
            if (pid == 0 || pid == 4)
            {
                return (false, "시스템 핵심 프로세스는 종료할 수 없습니다.");
            }

            try
            {
                // Task.Run을 통해 백그라운드 스레드에서 Kill 실행 (WinForms UI 응답성 향상)
                await Task.Run(() =>
                {
                    using var proc = Process.GetProcessById(pid);
                    proc.Kill(true); // 전체 트리 강제 종료
                });
                return (true, null);
            }
            catch (System.ComponentModel.Win32Exception)
            {
                return (false, "권한 없음 — 관리자 권한으로 실행하십시오.");
            }
            catch (ArgumentException)
            {
                return (false, "프로세스가 존재하지 않거나 이미 종료되었습니다.");
            }
            catch (Exception ex)
            {
                return (false, ex.Message);
            }
        }

        // 프로세스 강제 종료 (동기 버전)
        public (bool success, string? errorMessage) KillProcess(int pid)
        {
            return KillProcessAsync(pid).GetAwaiter().GetResult();
        }
    }
}
