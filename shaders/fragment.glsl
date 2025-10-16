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
    return texture2D(u_octreeTexture, vec2(x / 2.0 + 0.25, y / u_textureSize + 0.5 / u_textureSize));
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

        float nextNodeIndex = 0.0;
        if (current_child_idx == 0) nextNodeIndex = children1.x;
        else if (current_child_idx == 1) nextNodeIndex = children1.y;
        else if (current_child_idx == 2) nextNodeIndex = children1.z;
        else if (current_child_idx == 3) nextNodeIndex = children1.w;
        else if (current_child_idx == 4) nextNodeIndex = children2.x;
        else if (current_child_idx == 5) nextNodeIndex = children2.y;
        else if (current_child_idx == 6) nextNodeIndex = children2.z;
        else if (current_child_idx == 7) nextNodeIndex = children2.w;

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
    if (type < 1.5) return vec3(0.5, 0.3, 0.1);    // 1: Dirt
    if (type < 2.5) return vec3(0.5);              // 2: Stone
    if (type < 3.5) return vec3(0.2, 0.5, 1.0);    // 3: Water
    if (type < 4.5) return vec3(0.6, 0.4, 0.2);    // 4: Wood
    if (type < 5.5) return vec3(0.1, 0.6, 0.1);    // 5: Leaves
    if (type < 6.5) return vec3(0.8, 0.9, 1.0);    // 6: Glass
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

    vec3 col = vec3(0.0);
    float alpha = 0.0;
    const int MAX_TRANSPARENCY_BOUNCES = 4;

    vec3 current_ro = ro;
    vec3 current_rd = rd;

    for (int i = 0; i < MAX_TRANSPARENCY_BOUNCES; i++) {
        vec2 hit = traceOctree(current_ro, current_rd);
        float hit_t = hit.x;
        float voxel_type = hit.y;

        if (hit_t >= MAX_DIST) {
            // Hit sky
            float t = 0.5 + 0.5 * current_rd.y;
            vec3 skyColor = (1.0 - t) * vec3(1.0) + t * vec3(0.5, 0.7, 1.0);
            col += (1.0 - alpha) * skyColor;
            break;
        }

        vec3 p = current_ro + current_rd * hit_t;
        vec3 normal = calcNormal(p);

        bool is_transparent = voxel_type > 2.5 && voxel_type < 3.5 || voxel_type > 5.5 && voxel_type < 6.5;

        if (is_transparent) {
            vec3 voxelColor = getVoxelColor(voxel_type);
            float transparency = (voxel_type > 5.5) ? 0.2 : 0.4; // Glass is less transparent than water
            col += (1.0 - alpha) * transparency * voxelColor;
            alpha += (1.0 - alpha) * transparency;

            // Continue ray marching
            current_ro = p + current_rd * HIT_EPSILON;
        } else {
            // Opaque object, finish rendering
            vec3 lightDir = normalize(vec3(0.5, 1.0, -0.5));
            float diffuse = max(0.0, dot(normal, lightDir)) * 0.7 + 0.3;
            vec2 shadow_hit = traceOctree(p + normal * HIT_EPSILON, lightDir);
            float shadow_factor = (shadow_hit.x < MAX_DIST) ? 0.5 : 1.0;

            // --- Ambient Occlusion Calculation ---
            float ao_factor = 1.0 - (
                  traceOctree(p + normal * 0.2, normal).x < 0.2 ? 0.1 : 0.0
                + traceOctree(p + normal * 0.4, normal).x < 0.4 ? 0.1 : 0.0
                + traceOctree(p + normal * 0.8, normal).x < 0.8 ? 0.1 : 0.0
            );

            vec3 voxelColor = getVoxelColor(voxel_type);
            col += (1.0 - alpha) * voxelColor * diffuse * shadow_factor * ao_factor;
            alpha = 1.0; // Fully opaque
            break;
        }

        if (alpha > 0.99) break;
    }

    gl_FragColor = vec4(col, 1.0);
}