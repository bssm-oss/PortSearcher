using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using PortSearcherWin.Core;

namespace PortSearcherWin.CLI
{
    class Program
    {
        private static readonly PortScanner Scanner = new();
        private const string CurrentVersion = "1.4.0";
        private static string? _latestVersion = null;
        private static Task? _updateCheckTask = null;

        // HttpClient 싱글톤 적용 (소켓 고갈 및 리소스 누수 방지)
        private static readonly HttpClient HttpClientInstance = new()
        {
            Timeout = TimeSpan.FromSeconds(2)
        };

        static async Task Main(string[] args)
        {
            // 정적 헤더 설정 (최초 1회만 설정)
            if (!HttpClientInstance.DefaultRequestHeaders.UserAgent.Any())
            {
                HttpClientInstance.DefaultRequestHeaders.UserAgent.ParseAdd("PortSearcherCLI");
            }

            // 백그라운드 업데이트 체크 시작
            _updateCheckTask = Task.Run(CheckForUpdatesAsync);

            string command = args.Length > 0 ? args[0].ToLower() : "list";

            switch (command)
            {
                case "list":
                    await ListActivePortsAsync();
                    break;
                case "check":
                    if (args.Length < 2)
                    {
                        Console.WriteLine("오류: 포트 번호를 입력하세요. 예: pts check 8080");
                        Environment.Exit(1);
                    }
                    await CheckPortAsync(args[1]);
                    break;
                case "info":
                    if (args.Length < 2)
                    {
                        Console.WriteLine("오류: 포트 번호를 입력하세요. 예: pts info 8080");
                        Environment.Exit(1);
                    }
                    await PortInfoAsync(args[1]);
                    break;
                case "kill":
                    if (args.Length < 2)
                    {
                        Console.WriteLine("오류: 포트 번호를 입력하세요. 예: pts kill 8080");
                        Environment.Exit(1);
                    }
                    await KillPortAsync(args[1]);
                    break;
                case "version":
                case "--version":
                case "-v":
                    Console.WriteLine($"pts v{CurrentVersion}");
                    break;
                case "help":
                case "--help":
                case "-h":
                    PrintHelp();
                    break;
                default:
                    if (ushort.TryParse(command, out _))
                    {
                        await CheckPortAsync(command);
                    }
                    else
                    {
                        Console.WriteLine($"알 수 없는 명령어: {command}");
                        PrintHelp();
                        Environment.Exit(1);
                    }
                    break;
            }

            // 업데이트 체크 완료 대기 및 알림 (최대 1.5초 대기)
            if (_updateCheckTask != null)
            {
                try
                {
                    await Task.WhenAny(_updateCheckTask, Task.Delay(1500));
                }
                catch { /* 백그라운드 태스크 예외 무시 */ }
            }

            if (_latestVersion != null)
            {
                Console.WriteLine($"\n🆕 새 버전 v{_latestVersion} 출시! (현재 v{CurrentVersion})");
                Console.WriteLine("   다운로드: https://github.com/bssm-oss/PortSearcher/releases/latest");
            }
        }

        static void PrintHelp()
        {
            Console.WriteLine(@"PortSearcher CLI (Windows)

사용법:
  pts                    현재 사용 중인 포트 목록 출력
  pts check <포트번호>   특정 포트 사용 가능 여부 확인
  pts info  <포트번호>   해당 포트를 사용 중인 프로세스 정보
  pts kill  <포트번호>   해당 포트 프로세스 강제 종료
  pts help               도움말");
        }

        static async Task ListActivePortsAsync()
        {
            var ports = await Scanner.ActivePortsAsync();
            if (ports.Count == 0)
            {
                Console.WriteLine("사용 중인 포트가 없습니다.");
                return;
            }

            // 헤더 출력
            Console.WriteLine($"{"PORT",-8}{"PID",-10}{"PROTO",-8}{"UPTIME",-10}PROCESS");
            Console.WriteLine(new string('-', 54));

            foreach (var info in ports)
            {
                Console.WriteLine($"{info.Port,-8}{info.Pid,-10}{info.Protocol,-8}{info.Uptime,-10}{info.ProcessName}");
            }

            Console.WriteLine($"\n총 {ports.Count}개 포트 사용 중");
        }

        static async Task CheckPortAsync(string portStr)
        {
            if (!ushort.TryParse(portStr, out ushort port) || port == 0)
            {
                Console.WriteLine($"오류: '{portStr}'은(는) 올바른 포트 번호가 아닙니다. (1–65535)");
                Environment.Exit(1);
            }

            if (Scanner.IsPortAvailable(port))
            {
                Console.WriteLine($"✅ 포트 {port}: 사용 가능");
            }
            else
            {
                Console.WriteLine($"❌ 포트 {port}: 사용 중");
                var info = await Scanner.ProcessUsingAsync(port);
                if (info != null)
                {
                    Console.WriteLine($"   프로세스: {info.ProcessName} (PID: {info.Pid})");
                }
            }
        }

        static async Task PortInfoAsync(string portStr)
        {
            if (!ushort.TryParse(portStr, out ushort port) || port == 0)
            {
                Console.WriteLine("오류: 올바른 포트 번호가 아닙니다.");
                Environment.Exit(1);
            }

            var info = await Scanner.ProcessUsingAsync(port);
            if (info != null)
            {
                Console.WriteLine($"포트 {port} 정보:");
                Console.WriteLine($"  프로세스: {info.ProcessName}");
                Console.WriteLine($"  PID:     {info.Pid}");
                Console.WriteLine($"  프로토콜: {info.Protocol}");
                if (!string.IsNullOrEmpty(info.Uptime))
                {
                    Console.WriteLine($"  업타임:   {info.Uptime}");
                }
            }
            else if (Scanner.IsPortAvailable(port))
            {
                Console.WriteLine($"포트 {port}는 현재 사용 중이지 않습니다 (사용 가능).");
            }
            else
            {
                Console.WriteLine($"포트 {port}는 사용 중이지만 프로세스 정보를 가져올 수 없습니다.");
            }
        }

        static async Task KillPortAsync(string portStr)
        {
            if (!ushort.TryParse(portStr, out ushort port) || port == 0)
            {
                Console.WriteLine("오류: 올바른 포트 번호가 아닙니다.");
                Environment.Exit(1);
            }

            var info = await Scanner.ProcessUsingAsync(port);
            if (info == null)
            {
                Console.WriteLine($"포트 {port}는 사용 중이지 않습니다.");
                Environment.Exit(0);
            }

            Console.WriteLine($"종료 대상: {info.ProcessName} (PID: {info.Pid}) — 포트 {info.Port}");
            var (success, errMsg) = await Scanner.KillProcessAsync(info.Pid);
            if (success)
            {
                Console.WriteLine("✅ 프로세스 종료 완료");
            }
            else
            {
                Console.WriteLine($"❌ 종료 실패: {errMsg ?? "알 수 없는 오류"}");
                Environment.Exit(1);
            }
        }

        private static async Task CheckForUpdatesAsync()
        {
            try
            {
                // 공유 싱글톤 HttpClientInstance 사용
                string json = await HttpClientInstance.GetStringAsync("https://api.github.com/repos/bssm-oss/PortSearcher/releases/latest");
                
                // Native AOT 호환 수동 문자열 정규식 파싱
                var match = Regex.Match(json, @"""tag_name""\s*:\s*""([^""]+)""");
                if (match.Success)
                {
                    string tag = match.Groups[1].Value;
                    string latest = tag.StartsWith("v") ? tag.Substring(1) : tag;
                    
                    if (IsNewer(latest, CurrentVersion))
                    {
                        _latestVersion = latest;
                    }
                }
            }
            catch
            {
                // 실패 시 백그라운드이므로 침묵
            }
        }

        private static bool IsNewer(string latest, string current)
        {
            try
            {
                var l = latest.Split('.').Select(s => int.TryParse(s, out int val) ? val : 0).ToList();
                var c = current.Split('.').Select(s => int.TryParse(s, out int val) ? val : 0).ToList();

                for (int i = 0; i < Math.Max(l.Count, c.Count); i++)
                {
                    int lv = i < l.Count ? l[i] : 0;
                    int cv = i < c.Count ? c[i] : 0;
                    if (lv != cv) return lv > cv;
                }
            }
            catch
            {
                // 파싱 예외 발생 시 더 최신 버전이 아니라고 판단
            }
            return false;
        }
    }
}
