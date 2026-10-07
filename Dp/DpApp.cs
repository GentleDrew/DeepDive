using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

static class Program
{
    [DllImport("user32.dll")]
    static extern bool SetProcessDPIAware();

    [STAThread]
    static void Main()
    {
        bool created;
        using (Mutex m = new Mutex(true, "Dp.DrewPlanner.SingleInstance", out created))
        {
            if (!created) return;
            SetProcessDPIAware();
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new DpForm());
        }
    }
}

class DpForm : Form
{
    WebView2 wv;
    string dir;
    string html;

    public DpForm()
    {
        Text = "Dp";
        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        ClientSize = new Size(Math.Min(1500, wa.Width * 92 / 100), Math.Min(920, wa.Height * 92 / 100));
        MinimumSize = new Size(900, 600);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(13, 10, 29);
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }

        dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Dp");
        Directory.CreateDirectory(dir);
        html = Path.Combine(dir, "Dp.html");
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("Dp.html"))
        using (FileStream f = File.Create(html))
        {
            s.CopyTo(f);
        }

        wv = new WebView2();
        wv.Dock = DockStyle.Fill;
        wv.DefaultBackgroundColor = BackColor;
        Controls.Add(wv);
        Load += new EventHandler(OnFormLoad);
    }

    async void OnFormLoad(object sender, EventArgs e)
    {
        try
        {
            CoreWebView2Environment env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(dir, "wv2"));
            await wv.EnsureCoreWebView2Async(env);
            CoreWebView2 c = wv.CoreWebView2;
            c.Settings.AreDevToolsEnabled = false;
            c.Settings.AreDefaultContextMenusEnabled = false;
            c.Settings.IsStatusBarEnabled = false;
            c.SetVirtualHostNameToFolderMapping("dp.local", dir, CoreWebView2HostResourceAccessKind.Allow);
            c.Navigate("https://dp.local/Dp.html");
        }
        catch (Exception)
        {
            Fallback();
        }
    }

    void Fallback()
    {
        string uri = new Uri(html).AbsoluteUri;
        string pf = Environment.GetEnvironmentVariable("ProgramFiles");
        string pf86 = Environment.GetEnvironmentVariable("ProgramFiles(x86)");
        string[] browsers = {
            pf + "\\Microsoft\\Edge\\Application\\msedge.exe",
            pf86 + "\\Microsoft\\Edge\\Application\\msedge.exe",
            pf + "\\Google\\Chrome\\Application\\chrome.exe",
            pf86 + "\\Google\\Chrome\\Application\\chrome.exe"
        };
        foreach (string b in browsers)
        {
            if (!string.IsNullOrEmpty(b) && File.Exists(b))
            {
                Process.Start(b, "--app=\"" + uri + "\"");
                Close();
                return;
            }
        }
        ProcessStartInfo psi = new ProcessStartInfo(html);
        psi.UseShellExecute = true;
        Process.Start(psi);
        Close();
    }
}
