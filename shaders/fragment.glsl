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

    // --- Ray Marching ---
    vec2 hit1 = traceOctree(ro, rd);
    if (hit1.x >= MAX_DIST) {
        // Hit sky on first bounce
        float t = 0.5 + 0.5 * rd.y;
        col = (1.0 - t) * vec3(1.0) + t * vec3(0.5, 0.7, 1.0);
    } else {
        vec3 p1 = ro + rd * hit1.x;
        vec3 n1 = calcNormal(p1);
        float v_type1 = hit1.y;
        bool is_trans1 = v_type1 > 2.5 && v_type1 < 3.5 || v_type1 > 5.5 && v_type1 < 6.5;

        if (!is_trans1) {
            // Opaque hit
            vec3 lightDir = normalize(vec3(0.5, 1.0, -0.5));
            float diffuse = max(0.0, dot(n1, lightDir)) * 0.7 + 0.3;
            vec2 shadow_hit = traceOctree(p1 + n1 * HIT_EPSILON, lightDir);
            float shadow = shadow_hit.x < MAX_DIST ? 0.5 : 1.0;
            col = getVoxelColor(v_type1) * diffuse * shadow;
        } else {
            // Transparent hit, march again
            vec3 trans_col = getVoxelColor(v_type1);
            float trans_alpha = (v_type1 > 5.5) ? 0.2 : 0.4;
            col += trans_col * trans_alpha;
            alpha += trans_alpha;

            vec3 ro2 = p1 + rd * HIT_EPSILON;
            vec2 hit2 = traceOctree(ro2, rd);

            if (hit2.x >= MAX_DIST) {
                float t = 0.5 + 0.5 * rd.y;
                vec3 skyColor = (1.0 - t) * vec3(1.0) + t * vec3(0.5, 0.7, 1.0);
                col += (1.0 - alpha) * skyColor;
            } else {
                vec3 p2 = ro2 + rd * hit2.x;
                vec3 n2 = calcNormal(p2);
                float v_type2 = hit2.y;
                vec3 lightDir = normalize(vec3(0.5, 1.0, -0.5));
                float diffuse = max(0.0, dot(n2, lightDir)) * 0.7 + 0.3;
                vec2 shadow_hit = traceOctree(p2 + n2 * HIT_EPSILON, lightDir);
                float shadow = shadow_hit.x < MAX_DIST ? 0.5 : 1.0;
                col += (1.0 - alpha) * getVoxelColor(v_type2) * diffuse * shadow;
            }
        }
    }

    gl_FragColor = vec4(col, 1.0);
}