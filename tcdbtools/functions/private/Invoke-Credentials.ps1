# https://stackoverflow.com/questions/29103238/accessing-windows-credential-manager-from-powershell


$code = @"
using System.Text;
using System;
using System.Runtime.InteropServices;

namespace CredManager {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct CredentialMem
  {
    public int flags;
    public int type;
    public string targetName;
    public string comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME lastWritten;
    public int credentialBlobSize;
    public IntPtr credentialBlob;
    public int persist;
    public int attributeCount;
    public IntPtr credAttribute;
    public string targetAlias;
    public string userName;
  }

  public class Credential {
    public string target;
    public string username;
    public string password;
    public Credential(string target, string username, string password) {
      this.target = target;
      this.username = username;
      this.password = password;
    }
  }

  public class Util
  {
    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

    public static Credential GetUserCredential(string target)
    {
      CredentialMem credMem;
      IntPtr credPtr;

      if (CredRead(target, 1, 0, out credPtr))
      {
        credMem = Marshal.PtrToStructure<CredentialMem>(credPtr);
        byte[] passwordBytes = new byte[credMem.credentialBlobSize];
        Marshal.Copy(credMem.credentialBlob, passwordBytes, 0, credMem.credentialBlobSize);
        Credential cred = new Credential(credMem.targetName, credMem.userName, Encoding.Unicode.GetString(passwordBytes));
        return cred;
      } else {
        throw new Exception("Failed to retrieve credentials");
      }
    }

    [DllImport("Advapi32.dll", SetLastError = true, EntryPoint = "CredWriteW", CharSet = CharSet.Unicode)]
    private static extern bool CredWrite([In] ref CredentialMem userCredential, [In] int flags);

    public static void SetUserCredential(string target, string userName, string password)
    {
      CredentialMem userCredential = new CredentialMem();

      userCredential.targetName = target;
      userCredential.type = 1;
      userCredential.userName = userName;
      userCredential.attributeCount = 0;
      userCredential.persist = 3;
      byte[] bpassword = Encoding.Unicode.GetBytes(password);
      userCredential.credentialBlobSize = (int)bpassword.Length;
      userCredential.credentialBlob = Marshal.StringToCoTaskMemUni(password);
      if (!CredWrite(ref userCredential, 0))
      {
        throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      }
    }
  }
}
"@
Add-Type -TypeDefinition $code -Language CSharp
