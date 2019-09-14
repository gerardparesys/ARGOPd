// SketchSendOSC.pde
// 1-9-2018
//
// OK Processing 1.5
// OK Processing 2.0.3
// OK Processing 3.3.7
//
// Utilise la library oscP5 0.9.9 by andreas schlegel  
// http://www.sojamo.de/oscP5
//
// mousePressed pour envoyer un message OSC: /argo 123 ...
//              sur le port 12000    

import oscP5.*;
import netP5.*;

OscP5 oscP5;
NetAddress myRemoteLocation;

int Nombre = 0;

void setup() {
  size(100, 100);
  /* start oscP5, listening for incoming messages at port 12000 */
  oscP5 = new OscP5(this, 12000);
  myRemoteLocation = new NetAddress("127.0.0.1", 12000);
}


void draw() {
  background(0);
}

void mousePressed() {
  Nombre = Nombre + 123;
  OscMessage MonMessage = new OscMessage("/argo");
  MonMessage.add(Nombre);  // add an int to the osc message
  oscP5.send(MonMessage, myRemoteLocation);
}
