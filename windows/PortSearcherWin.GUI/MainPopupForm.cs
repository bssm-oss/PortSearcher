using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using PortSearcherWin.Core;

namespace PortSearcherWin.GUI
{
    public class MainPopupForm : Form
    {
        private readonly PortScanner _scanner = new();
        private List<PortInfo> _allPorts = new();
        private CancellationTokenSource? _cts;

        // UI Controls
        private Panel _pnlHeader = null!;
        private Label _lblTitle = null!;
        private Label _lblStatus = null!;
        private Button _btnRefresh = null!;

        private Panel _pnlCheck = null!;
        private TextBox _txtCheckInput = null!;
        private Button _btnCheck = null!;
        private Panel _pnlCheckResult = null!;
        private Label _lblCheckResult = null!;

        private Panel _pnlSearch = null!;
        private TextBox _txtSearch = null!;

        private DataGridView _dgvPorts = null!;

        public MainPopupForm()
        {
            InitializeComponent();
        }

        private void InitializeComponent()
        {
            // 폼 속성 설정
            this.Size = new Size(420, 520);
            this.FormBorderStyle = FormBorderStyle.None;
            this.ShowInTaskbar = false;
            this.StartPosition = FormStartPosition.Manual;
            this.BackColor = SystemColors.Window;
            this.Font = new Font("Segoe UI", 9F, FontStyle.Regular);

            // Form 더블 버퍼링 설정 (깜빡임 방지)
            this.DoubleBuffered = true;

            // 포커스를 잃으면 자동으로 닫히는 동작 (Transient)
            this.Deactivate += (s, e) => this.Hide();

            // 1. 헤더 영역
            _pnlHeader = new Panel { Dock = DockStyle.Top, Height = 45, Padding = new Padding(12, 8, 12, 8) };
            _lblTitle = new Label 
            { 
                Text = "PortSearcher", 
                Font = new Font("Segoe UI", 10F, FontStyle.Bold), 
                Location = new Point(12, 12),
                AutoSize = true 
            };
            _lblStatus = new Label 
            { 
                Text = "준비 중...", 
                ForeColor = SystemColors.GrayText, 
                Location = new Point(110, 14), 
                AutoSize = true 
            };
            _btnRefresh = new Button 
            { 
                Text = "🔄", 
                Size = new Size(26, 26), 
                Location = new Point(382, 9), 
                FlatStyle = FlatStyle.Flat 
            };
            _btnRefresh.FlatAppearance.BorderSize = 0;
            _btnRefresh.Click += async (s, e) => await RefreshPortsAsync();

            _pnlHeader.Controls.Add(_lblTitle);
            _pnlHeader.Controls.Add(_lblStatus);
            _pnlHeader.Controls.Add(_btnRefresh);

            var div1 = new Label { Dock = DockStyle.Top, Height = 1, BorderStyle = BorderStyle.FixedSingle, Text = "" };

            // 2. 포트 개별 진단 영역 (Check Panel)
            _pnlCheck = new Panel { Dock = DockStyle.Top, Height = 80, Padding = new Padding(12, 8, 12, 8), BackColor = SystemColors.ControlLightLight };
            _txtCheckInput = new TextBox 
            { 
                Location = new Point(12, 10), 
                Width = 290, 
                Font = new Font("Consolas", 10F),
                PlaceholderText = "포트 번호 입력 후 Enter"
            };
            _txtCheckInput.KeyDown += async (s, e) => { if (e.KeyCode == Keys.Enter) await CheckPortAsync(); };

            _btnCheck = new Button 
            { 
                Text = "확인", 
                Location = new Point(310, 8), 
                Width = 98, 
                Height = 28,
                FlatStyle = FlatStyle.System
            };
            _btnCheck.Click += async (s, e) => await CheckPortAsync();

            _pnlCheckResult = new Panel 
            { 
                Location = new Point(12, 42), 
                Width = 396, 
                Height = 32, 
                Visible = false,
                Padding = new Padding(8, 6, 8, 6)
            };
            _lblCheckResult = new Label { Dock = DockStyle.Fill, AutoSize = false, TextAlign = ContentAlignment.MiddleLeft, Font = new Font("Segoe UI", 9F, FontStyle.Bold) };
            _pnlCheckResult.Controls.Add(_lblCheckResult);

            _pnlCheck.Controls.Add(_txtCheckInput);
            _pnlCheck.Controls.Add(_btnCheck);
            _pnlCheck.Controls.Add(_pnlCheckResult);

            var div2 = new Label { Dock = DockStyle.Top, Height = 1, BorderStyle = BorderStyle.FixedSingle, Text = "" };

            // 3. 검색 영역
            _pnlSearch = new Panel { Dock = DockStyle.Top, Height = 40, Padding = new Padding(12, 8, 12, 8) };
            _txtSearch = new TextBox 
            { 
                Dock = DockStyle.Fill, 
                PlaceholderText = "🔍 포트 번호, 프로세스명, PID 검색...",
                Font = new Font("Segoe UI", 9.5F)
            };
            _txtSearch.TextChanged += (s, e) => FilterPorts();
            _pnlSearch.Controls.Add(_txtSearch);

            var div3 = new Label { Dock = DockStyle.Top, Height = 1, BorderStyle = BorderStyle.FixedSingle, Text = "" };

            // 4. 포트 리스트 그리드 (DataGridView)
            _dgvPorts = new DataGridView
            {
                Dock = DockStyle.Fill,
                BackgroundColor = SystemColors.Window,
                BorderStyle = BorderStyle.None,
                RowHeadersVisible = false,
                AllowUserToAddRows = false,
                AllowUserToDeleteRows = false,
                ReadOnly = true,
                SelectionMode = DataGridViewSelectionMode.FullRowSelect,
                MultiSelect = false,
                GridColor = SystemColors.ControlLight,
                CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal,
                ColumnHeadersBorderStyle = DataGridViewHeaderBorderStyle.None,
                AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
                RowTemplate = { Height = 32 }
            };

            // DataGridView 더블 버퍼링 리플렉션 적용 (그리드 스크롤 및 갱신 깜빡임 극단적 제거)
            typeof(DataGridView)
                .GetProperty("DoubleBuffered", BindingFlags.Instance | BindingFlags.NonPublic)
                ?.SetValue(_dgvPorts, true, null);
            
            _dgvPorts.ColumnHeadersDefaultCellStyle.BackColor = SystemColors.Control;
            _dgvPorts.ColumnHeadersDefaultCellStyle.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
            _dgvPorts.ColumnHeadersDefaultCellStyle.ForeColor = SystemColors.WindowText;
            _dgvPorts.EnableHeadersVisualStyles = false;

            _dgvPorts.Columns.Add(new DataGridViewTextBoxColumn { Name = "Port", HeaderText = "PORT", FillWeight = 50 });
            _dgvPorts.Columns.Add(new DataGridViewTextBoxColumn { Name = "Process", HeaderText = "PROCESS", FillWeight = 110 });
            _dgvPorts.Columns.Add(new DataGridViewTextBoxColumn { Name = "Pid", HeaderText = "PID", FillWeight = 50 });
            _dgvPorts.Columns.Add(new DataGridViewTextBoxColumn { Name = "Proto", HeaderText = "PROTO", FillWeight = 50 });
            _dgvPorts.Columns.Add(new DataGridViewTextBoxColumn { Name = "Uptime", HeaderText = "UPTIME", FillWeight = 60 });
            
            var btnCol = new DataGridViewButtonColumn
            {
                Name = "Kill",
                HeaderText = "ACTION",
                Text = "종료",
                UseColumnTextForButtonValue = true,
                FillWeight = 50,
                FlatStyle = FlatStyle.Flat
            };
            btnCol.DefaultCellStyle.ForeColor = Color.Red;
            btnCol.DefaultCellStyle.SelectionForeColor = Color.Red;
            _dgvPorts.Columns.Add(btnCol);

            _dgvPorts.CellContentClick += async (s, e) => await OnGridCellContentClickAsync(s, e);
            _dgvPorts.CellClick += async (s, e) =>
            {
                if (e.RowIndex >= 0 && e.ColumnIndex != _dgvPorts.Columns["Kill"]!.Index)
                {
                    var portCell = _dgvPorts.Rows[e.RowIndex].Cells["Port"].Value;
                    if (portCell != null)
                    {
                        _txtCheckInput.Text = portCell.ToString();
                        await CheckPortAsync();
                    }
                }
            };

            // 하단 바
            var pnlBottom = new Panel { Dock = DockStyle.Bottom, Height = 30, Padding = new Padding(12, 4, 12, 4) };
            var lblFooter = new Label
            {
                Text = "PortSearcher v1.4.0 (Windows)",
                ForeColor = SystemColors.GrayText,
                Font = new Font("Segoe UI", 8F),
                Dock = DockStyle.Left,
                TextAlign = ContentAlignment.MiddleLeft
            };
            var btnExit = new Button
            {
                Text = "종료",
                Size = new Size(50, 22),
                Dock = DockStyle.Right,
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Segoe UI", 8F)
            };
            btnExit.FlatAppearance.BorderSize = 0;
            btnExit.Click += (s, e) => Application.Exit();

            pnlBottom.Controls.Add(lblFooter);
            pnlBottom.Controls.Add(btnExit);

            this.Controls.Add(_dgvPorts);
            this.Controls.Add(div3);
            this.Controls.Add(_pnlSearch);
            this.Controls.Add(div2);
            this.Controls.Add(_pnlCheck);
            this.Controls.Add(div1);
            this.Controls.Add(_pnlHeader);
            this.Controls.Add(pnlBottom);
        }

        // 트레이 클릭 시 팝업 열기
        public async void ShowPopup()
        {
            var workingArea = Screen.PrimaryScreen!.WorkingArea;
            int x = workingArea.Right - this.Width - 10;
            int y = workingArea.Bottom - this.Height - 10;

            this.Location = new Point(x, y);
            this.Show();
            this.Activate();
            
            await RefreshPortsAsync();
        }

        // 비동기 포트 리스트 갱신 (GUI가 멈추지 않음)
        private async Task RefreshPortsAsync()
        {
            // 진행 중인 이전 비동기 작업 취소
            _cts?.Cancel();
            _cts = new CancellationTokenSource();
            var token = _cts.Token;

            // 로딩 상태 피드백 UI 제공
            _btnRefresh.Enabled = false;
            _btnRefresh.Text = "⏳";
            _lblStatus.Text = "포트 분석 중...";

            try
            {
                var ports = await _scanner.ActivePortsAsync(token);
                
                // 취소되지 않은 경우에만 데이터 반영
                if (!token.IsCancellationRequested)
                {
                    _allPorts = ports;
                    _lblStatus.Text = $"{_allPorts.Count}개 사용 중";
                    FilterPorts();
                }
            }
            catch (OperationCanceledException)
            {
                // 작업 취소됨 - 무시
            }
            catch (Exception ex)
            {
                _lblStatus.Text = "갱신 실패";
                MessageBox.Show($"포트 정보를 가져오는 중 에러 발생: {ex.Message}", "오류", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                if (!token.IsCancellationRequested)
                {
                    _btnRefresh.Text = "🔄";
                    _btnRefresh.Enabled = true;
                }
            }
        }

        // 필터링
        private void FilterPorts()
        {
            string query = _txtSearch.Text.Trim();
            var filtered = _allPorts;

            if (!string.IsNullOrEmpty(query))
            {
                filtered = _allPorts.Where(p => 
                    p.Port.ToString().Contains(query) ||
                    p.ProcessName.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                    p.Pid.ToString().Contains(query)
                ).ToList();
            }

            _dgvPorts.Rows.Clear();
            foreach (var info in filtered)
            {
                _dgvPorts.Rows.Add(info.Port, info.ProcessName, info.Pid, info.Protocol, info.Uptime);
            }
        }

        // 비동기 포트 개별 진단
        private async Task CheckPortAsync()
        {
            string raw = _txtCheckInput.Text.Trim();
            if (!ushort.TryParse(raw, out ushort port) || port == 0)
            {
                ShowCheckResult("1–65535 사이 숫자를 입력하세요.", Color.Orange, Color.FromArgb(255, 243, 230));
                return;
            }

            _btnCheck.Enabled = false;
            try
            {
                bool available = _scanner.IsPortAvailable(port);
                var info = await _scanner.ProcessUsingAsync(port);

                if (available)
                {
                    ShowCheckResult($"포트 {port} — 사용 가능 (정상)", Color.Green, Color.FromArgb(230, 245, 230));
                }
                else
                {
                    string procInfo = info != null ? $"{info.ProcessName} · PID {info.Pid}" : "알 수 없는 프로세스";
                    ShowCheckResult($"포트 {port} — 사용 중\n({procInfo})", Color.Red, Color.FromArgb(255, 230, 230));
                }
            }
            finally
            {
                _btnCheck.Enabled = true;
            }
        }

        private void ShowCheckResult(string message, Color textForeColor, Color backColor)
        {
            _pnlCheckResult.Visible = true;
            _pnlCheckResult.BackColor = backColor;
            _lblCheckResult.Text = message;
            _lblCheckResult.ForeColor = textForeColor;
        }

        // 그리드 내 종료 버튼 비동기 클릭 핸들러
        private async Task OnGridCellContentClickAsync(object? sender, DataGridViewCellEventArgs e)
        {
            if (e.RowIndex >= 0 && e.ColumnIndex == _dgvPorts.Columns["Kill"]!.Index)
            {
                var portCell = _dgvPorts.Rows[e.RowIndex].Cells["Port"].Value;
                var pidCell = _dgvPorts.Rows[e.RowIndex].Cells["Pid"].Value;
                var nameCell = _dgvPorts.Rows[e.RowIndex].Cells["Process"].Value;

                if (portCell == null || pidCell == null) return;

                ushort port = (ushort)portCell;
                int pid = (int)pidCell;
                string processName = nameCell?.ToString() ?? "Unknown";

                var confirmResult = MessageBox.Show(
                    $"포트 {port} 프로세스를 종료할까요?\n\n대상: {processName} (PID: {pid})를 강제 종료합니다.",
                    "프로세스 강제 종료",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Warning
                );

                if (confirmResult == DialogResult.Yes)
                {
                    var (success, errMsg) = await _scanner.KillProcessAsync(pid);
                    if (success)
                    {
                        // 프로세스가 시스템에서 완전히 언마운트되는 미세한 딜레이 부여 후 비동기 새로고침
                        await Task.Delay(400);
                        await RefreshPortsAsync();
                    }
                    else
                    {
                        MessageBox.Show(
                            $"종료 실패: {errMsg ?? "알 수 없는 오류"}",
                            "오류",
                            MessageBoxButtons.OK,
                            MessageBoxIcon.Error
                        );
                    }
                }
            }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            _cts?.Cancel();
            _cts?.Dispose();
            base.OnFormClosing(e);
        }
    }
}
