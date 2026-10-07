using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

static class DpLauncher
{
    [STAThread]
    static void Main()
    {
        string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Dp");
        Directory.CreateDirectory(dir);
        string html = Path.Combine(dir, "Dp.html");
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("Dp.html"))
        using (FileStream f = File.Create(html))
        {
            s.CopyTo(f);
        }
        string uri = new Uri(html).AbsoluteUri;
        string pf = Environment.GetEnvironmentVariable("ProgramFiles");
        string pf86 = Environment.GetEnvironmentVariable("ProgramFiles(x86)");
        string la = Environment.GetEnvironmentVariable("LOCALAPPDATA");
        string[] browsers = {
            pf + "\\Microsoft\\Edge\\Application\\msedge.exe",
            pf86 + "\\Microsoft\\Edge\\Application\\msedge.exe",
            pf + "\\Google\\Chrome\\Application\\chrome.exe",
            pf86 + "\\Google\\Chrome\\Application\\chrome.exe",
            la + "\\Google\\Chrome\\Application\\chrome.exe"
        };
        foreach (string b in browsers)
        {
            if (!string.IsNullOrEmpty(b) && File.Exists(b))
            {
                Process.Start(b, "--app=\"" + uri + "\"");
                return;
            }
        }
        ProcessStartInfo psi = new ProcessStartInfo(html);
        psi.UseShellExecute = true;
        Process.Start(psi);
    }
}
