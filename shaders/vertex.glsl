// BTV-E - vertex.glsl
// This shader will be simple, just passing through vertex positions.
attribute vec4 a_position;

void main() {
    gl_Position = a_position;
}