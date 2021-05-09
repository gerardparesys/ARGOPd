// SketchReceiveOSC.pde
// 9 5 2021
//
// OK Processing 1.5.1 Windows 10
// OK Processing 3.3.7 mode Java Ubuntu & MacOS
// OK en local ou sur reseau 
// OK Processing 3.3.7 mode Android
//           Menu Android -> Sketch Permissions -> INTERNET  
//
// Utilise la library oscP5 0.9.9 by andreas schlegel  
// http://www.sojamo.de/oscP5
// Utilise la  library Ketai
// http://ketai.org
//

int PortOSC = 12000;
String Chaine = ""; 
import oscP5.*;
import ketai.net.*;

OscP5 oscP5;

void setup() {
  size(500, 500);
  // fullScreen();
  noStroke();
  // start oscP5, listening for incoming messages at port 12000
  oscP5 = new OscP5(this, PortOSC);
  // osc messages with a specific address pattern can be automatically
  // forwarded to a specific method of an object.
  // a message with address pattern /argo will be forwarded to MethodeTest
  oscP5.plug(this, "MethodeTest", "/argo");
}

void draw() {
  background(0);
  textSize(24);
  fill(255, 0, 0);            // Rouge
  textAlign(CENTER, TOP);       //RIGHT LEFT BOTTOM BASELINE TOP
  text("LOCAL IP: " + KetaiNet.getIP(), width/2, 90);
  text("PortOSC: " + PortOSC, width/2, 150);
  text("Message reçu par OSC:", width/2, 180);
  text(Chaine, width/2, 210);
}

public void MethodeTest(String Chainex) {
  Chaine = Chainex;
  println("Received a message /argo    1 string received: "+ Chaine);
}
