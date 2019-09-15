// SketchSendOSCx8.pde
// 24-7-2018
//
// 
// OK Processing 2.0.3
// OK Processing 3.3.7
//
// Utilise la library oscP5 0.9.9 by andreas schlegel  
// http://www.sojamo.de/oscP5
//
// mousePressed pour envoyer un message OSC: /argo/X Y ...
//              sur le port 12000    
// X = 0 .. 7   = 4 zones horizontales
// Y = 0 .. 255 = Vertical Mouse

import oscP5.*;
import netP5.*;

OscP5 oscP5;
NetAddress myRemoteLocation;

int X = 0, Y = 0;

void setup() {
  size(800, 255);
  /* start oscP5, listening for incoming messages at port 12000 */
  oscP5 = new OscP5(this, 12000);
  myRemoteLocation = new NetAddress("127.0.0.1", 12000);
  textSize(32);
  fill(50);
}

void draw() {
  background(255);
  for (int i = 0; i < 8; i = i+1) {
    line(i*100, 0, i*100, height);
    text(i+1, i*100 + 42, 30);
    if (mouseX > i*100) X = i;
  }
  if (mousePressed) {
    Y = height - mouseY;
    println("X = " + X + "    Y = " + Y);
    OscMessage MonMessage = new OscMessage("/argo/" + X);
    MonMessage.add(Y);  // add an int to the osc message
    oscP5.send(MonMessage, myRemoteLocation);
  }
}
