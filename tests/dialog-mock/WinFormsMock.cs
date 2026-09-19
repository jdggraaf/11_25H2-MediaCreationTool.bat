#pragma warning disable 67, 649, 414
using System; using System.Collections.Generic; using System.Collections; 
namespace Drawing {
  public enum FontStyle { Regular=0, Bold=1 }
  public class Font { public string Name; public float Size; public FontStyle Style; public Font(string n, float s){Name=n;Size=s;} public Font(string n,float s,FontStyle st){Name=n;Size=s;Style=st;} public static implicit operator Font(string s){var p=s.Split(',');return new Font(p[0], p.Length>1?float.Parse(p[1]):9f);} public override string ToString(){return Name+","+Size;} }
  public struct Point { public int X,Y; public Point(int x,int y){X=x;Y=y;} public static implicit operator Point(string s){var p=s.Split(',');return new Point(int.Parse(p[0]),int.Parse(p[1]));} public override string ToString(){return X+","+Y;} }
  public struct Size { public int Width,Height; public Size(int w,int h){Width=w;Height=h;} public static implicit operator Size(string s){var p=s.Split(',');return new Size(int.Parse(p[0]),int.Parse(p[1]));} public override string ToString(){return Width+","+Height;} }
}
namespace Windows.Forms {
  public static class Application { public static void EnableVisualStyles(){} }
  public class ControlCollection : List<Control> {}
  public class ItemCollection : ArrayList {}
  public class Control {
    public string Text=""; public Drawing.Point Location; public Drawing.Size Size; public Drawing.Font Font; public bool AutoSize; public string ForeColor; public string BackColor;
    public bool Enabled=true; public bool Visible=true; public int Width { get{return Size.Width;} set{Size.Width=value;} } public int Height { get{return Size.Height;} set{Size.Height=value;} }
    public string Name; public string Cursor; public string Margin; public bool TabStop=true;
    public void Focus(){} 
    public event EventHandler TextChanged; public event EventHandler CheckedChanged; public event EventHandler Shown; public event EventHandler GotFocus; public event EventHandler LostFocus; public event EventHandler Click;
    public void FireTextChanged(){ if(TextChanged!=null) TextChanged(this,EventArgs.Empty);} public void FireCheckedChanged(){ if(CheckedChanged!=null) CheckedChanged(this,EventArgs.Empty);} public void FireShown(){ if(Shown!=null) Shown(this,EventArgs.Empty);} public void FireClick(){ if(Click!=null) Click(this,EventArgs.Empty);} public void FireGotFocus(){ if(GotFocus!=null) GotFocus(this,EventArgs.Empty);} public void FireLostFocus(){ if(LostFocus!=null) LostFocus(this,EventArgs.Empty);} 
  }
  public class Form : Control { public string StartPosition; public string FormBorderStyle; public bool MaximizeBox=true, MinimizeBox=true; public Drawing.Size ClientSize; public ControlCollection Controls=new ControlCollection(); public Button AcceptButton, CancelButton; public bool AutoSize2; public int AutoSizeMode; public static string NextResult="OK";
    public static List<int> ClickQueue = new List<int>();
    public string ShowDialog(){ FireShown();
      if (ClickQueue.Count > 0) { int i = ClickQueue[0]; ClickQueue.RemoveAt(0); if (i >= 0 && i < Controls.Count) Controls[i].FireClick(); }
      return NextResult; } public void Close(){} public void Activate(){} }
  public class Label : Control {}
  public class Button : Control { public string DialogResult; public int FlatStyle; public Drawing.Size MinimumSize; public void PerformClick(){} }
  public class ListBox : Control { public ItemCollection Items=new ItemCollection(); public int SelectedIndex=-1; public bool IntegralHeight=true; }
  public class RadioButton : Control { public bool Checked; }
  public class CheckBox : Control { public bool Checked; }
  public class ComboBox : Control { public ItemCollection Items=new ItemCollection(); public int SelectedIndex=-1; public string DropDownStyle; public new string Text { get { return SelectedIndex>=0 && SelectedIndex<Items.Count ? Items[SelectedIndex].ToString() : _t; } set { _t=value; SelectedIndex=-1; } } string _t=""; }
  public class TextBox : Control { public string CharacterCasing; public int MaxLength; }
}
