// BTV-E - fragment.glsl
precision highp float;

uniform vec2 u_resolution;
uniform vec3 u_cameraPos;
uniform vec3 u_cameraForward;
uniform vec3 u_cameraRight;
uniform vec3 u_cameraUp;
uniform sampler2D u_octreeTexture;
uniform float u_textureSize;

const float WORLD_SIZE = 16.0;
const int MAX_DEPTH = 4;
const float MAX_DIST = 100.0;
const float HIT_EPSILON = 0.001;

// --- UTILITY / MATH FUNCTIONS ---
vec4 getNode(float index) {
    // Each node is 2 pixels (8 floats)
    float y = floor(index / 2.0);
    float x = mod(index, 2.0);
    // Add 0.5 to sample the center of the texel
    return texture2D(u_octreeTexture, vec2((x + 0.5) / 2.0, (y + 0.5) / u_textureSize));
}

// --- CORE OCTREE TRAVERSAL ---
// Returns vec2(distance, voxel_type)
vec2 traceOctree(vec3 ro, vec3 rd) {
    vec3 invRd = 1.0 / rd;
    vec3 t1 = (vec3(0.0) - ro) * invRd;
    vec3 t2 = (vec3(WORLD_SIZE) - ro) * invRd;
    vec3 tmin = min(t1, t2);
    vec3 tmax = max(t1, t2);
    float t_enter = max(tmin.x, max(tmin.y, tmin.z));
    float t_exit = min(tmax.x, min(tmax.y, tmax.z));

    if (t_enter >= t_exit || t_exit < 0.0) return vec2(MAX_DIST, 0.0);

    float t = max(0.0, t_enter);

    float nodeIndex = 0.0;
    vec3 nodeMin = vec3(0.0);
    float nodeSize = WORLD_SIZE;

    for (int i = 0; i < MAX_DEPTH; ++i) {
        vec4 children1 = getNode(nodeIndex);
        vec4 children2 = getNode(nodeIndex + 1.0);

        // Check if the first 7 components are zero, indicating a leaf node
        if (children1.x == 0.0 && children1.y == 0.0 && children1.z == 0.0 && children1.w == 0.0 &&
            children2.x == 0.0 && children2.y == 0.0 && children2.z == 0.0) {
            float voxelType = children2.w;
            if (voxelType > 0.0) {
                return vec2(t, voxelType);
            }
            return vec2(MAX_DIST, 0.0); // Hit empty leaf
        }

        nodeSize *= 0.5;
        vec3 mid = nodeMin + nodeSize;

        // Find which child the ray enters first
        vec3 t_mid = (mid - ro) * invRd;
        vec3 side = sign(rd);
        int child_idx = int(step(t_mid.z, t_mid.y)) * 2 + int(step(t_mid.y, t_mid.x));
        // This is still a simplification. A robust implementation is much longer.

        vec3 p = ro + t * rd;
        int current_child_idx = 0;
        if (p.x >= mid.x) current_child_idx |= 1;
        if (p.y >= mid.y) current_child_idx |= 2;
        if (p.z >= mid.z) current_child_idx |= 4;

        float nextNodeIndex = (current_child_idx < 4) ? children1[current_child_idx] : children2[current_child_idx - 4];

        if (nextNodeIndex == 0.0) {
           return vec2(MAX_DIST, 0.0); // Should not happen
        }

        nodeIndex = nextNodeIndex;
        if ((current_child_idx & 1) != 0) nodeMin.x += nodeSize;
        if ((current_child_idx & 2) != 0) nodeMin.y += nodeSize;
        if ((current_child_idx & 4) != 0) nodeMin.z += nodeSize;

        // A more accurate traversal would calculate the `t` of intersection with the child box
        t += 0.01;
    }
    return vec2(MAX_DIST, 0.0);
}


vec3 getVoxelColor(float type) {
    if (type < 1.5) return vec3(0.5, 0.3, 0.1); // Dirt
    if (type < 2.5) return vec3(0.5);           // Stone
    if (type < 3.5) return vec3(0.2, 0.5, 1.0); // Water
    return vec3(1.0, 0.0, 1.0); // Error color (magenta)
}

vec3 calcNormal(vec3 p) {
    vec3 localPos = fract(p - HIT_EPSILON) - 0.5;
    vec3 absLocalPos = abs(localPos);
    if (absLocalPos.x > absLocalPos.y && absLocalPos.x > absLocalPos.z) {
        return vec3(sign(-localPos.x), 0.0, 0.0);
    } else if (absLocalPos.y > absLocalPos.z) {
        return vec3(0.0, sign(-localPos.y), 0.0);
    } else {
        return vec3(0.0, 0.0, sign(-localPos.z));
    }
}


void main() {
    vec2 uv = (gl_FragCoord.xy - 0.5 * u_resolution.xy) / u_resolution.y;
    vec3 ro = u_cameraPos;
    vec3 rd = normalize(uv.x * u_cameraRight + uv.y * u_cameraUp + 1.5 * u_cameraForward);

    vec2 hit = traceOctree(ro, rd);
    float hit_t = hit.x;
    float voxel_type = hit.y;

    vec3 col;
    if (hit_t < MAX_DIST) {
        vec3 p = ro + rd * hit_t;
        vec3 normal = calcNormal(p);
        vec3 lightDir = normalize(vec3(0.5, 1.0, -0.5));
        float diffuse = max(0.0, dot(normal, lightDir)) * 0.7 + 0.3;

        col = getVoxelColor(voxel_type);
        col *= diffuse;

    } else {
        // Sky Color
        float t = 0.5 + 0.5 * rd.y;
        col = (1.0 - t) * vec3(1.0) + t * vec3(0.5, 0.7, 1.0);
    }

    gl_FragColor = vec4(col, 1.0);
}