// LaptopPet.exe: pet.ps1 is embedded inside. On launch it is copied to
// %LOCALAPPDATA%\LaptopPet\pet.ps1 (pets.json is saved there too) and run with a hidden PowerShell.
// If an auto-update already put a newer pet.ps1 there, that one is kept.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

[assembly: AssemblyTitle("Laptop Pet")]
[assembly: AssemblyProduct("Laptop Pet")]

class Program
{
    static int VersionOf(string text)
    {
        Match m = Regex.Match(text, @"(?m)^\$AppVersion = (\d+)");
        return m.Success ? int.Parse(m.Groups[1].Value) : 0;
    }

    [STAThread]
    static void Main()
    {
        string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LaptopPet");
        Directory.CreateDirectory(dir);
        string script = Path.Combine(dir, "pet.ps1");
        byte[] embedded;
        using (Stream src = Assembly.GetExecutingAssembly().GetManifestResourceStream("pet.ps1"))
        using (MemoryStream ms = new MemoryStream())
        {
            src.CopyTo(ms);
            embedded = ms.ToArray();
        }
        int local = File.Exists(script) ? VersionOf(File.ReadAllText(script, Encoding.UTF8)) : -1;
        if (VersionOf(Encoding.UTF8.GetString(embedded)) >= local)
            File.WriteAllBytes(script, embedded);
        ProcessStartInfo psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"");
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        Process.Start(psi);
    }
}
