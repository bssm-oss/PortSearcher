using System;
using System.Drawing;
using System.Windows.Forms;

namespace PortSearcherWin.GUI
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            
            // Custom ApplicationContext를 이용해 실행창 없이 트레이에서 시작
            Application.Run(new TrayApplicationContext());
        }
    }

    public class TrayApplicationContext : ApplicationContext
    {
        private NotifyIcon _notifyIcon;
        private MainPopupForm? _popupForm;

        public TrayApplicationContext()
        {
            // 컨텍스트 메뉴 설정
            var contextMenu = new ContextMenuStrip();
            contextMenu.Items.Add("열기", null, OnOpenClicked);
            contextMenu.Items.Add(new ToolStripSeparator());
            contextMenu.Items.Add("종료", null, OnExitClicked);

            // 트레이 아이콘 설정
            _notifyIcon = new NotifyIcon
            {
                // Windows 기본 네트워크 아이콘 사용 (에셋이 따로 없는 경우 안전한 대안)
                Icon = SystemIcons.Application,
                ContextMenuStrip = contextMenu,
                Text = "PortSearcher",
                Visible = true
            };

            // 트레이 아이콘 클릭 시 토글 동작 추가 (마우스 클릭 좌표 획득용)
            _notifyIcon.MouseClick += OnTrayIconMouseClick;
        }

        private void OnTrayIconMouseClick(object? sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                TogglePopup();
            }
        }

        private void OnOpenClicked(object? sender, EventArgs e)
        {
            ShowPopup();
        }

        private void TogglePopup()
        {
            if (_popupForm != null && _popupForm.Visible)
            {
                _popupForm.Hide();
            }
            else
            {
                ShowPopup();
            }
        }

        private void ShowPopup()
        {
            if (_popupForm == null || _popupForm.IsDisposed)
            {
                _popupForm = new MainPopupForm();
            }

            _popupForm.ShowPopup();
        }

        private void OnExitClicked(object? sender, EventArgs e)
        {
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            
            if (_popupForm != null && !_popupForm.IsDisposed)
            {
                _popupForm.Dispose();
            }

            ExitThread();
        }
    }
}
