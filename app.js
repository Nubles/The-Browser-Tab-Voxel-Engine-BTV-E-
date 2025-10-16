// BTV-E - app.js

// --- OCTREE IMPLEMENTATION (from previous step) ---
class OctreeNode {
    constructor(bounds, depth) {
        this.bounds = bounds; this.depth = depth; this.children = []; this.isLeaf = true; this.data = null;
    }
    subdivide() {
        this.isLeaf = false;
        const halfSize = (this.bounds.max[0] - this.bounds.min[0]) / 2;
        for (let i = 0; i < 8; i++) {
            const newMin = [...this.bounds.min];
            if (i & 1) newMin[0] += halfSize; if (i & 2) newMin[1] += halfSize; if (i & 4) newMin[2] += halfSize;
            const newMax = [newMin[0] + halfSize, newMin[1] + halfSize, newMin[2] + halfSize];
            this.children[i] = new OctreeNode({ min: newMin, max: newMax }, this.depth + 1);
        }
    }
}
class Octree {
    constructor(worldSize, maxDepth) {
        this.root = new OctreeNode({ min: [0, 0, 0], max: [worldSize, worldSize, worldSize] }, 0);
        this.maxDepth = maxDepth;
    }
    _getChildIndex(point, node) {
        const mid = [
            node.bounds.min[0] + (node.bounds.max[0] - node.bounds.min[0]) / 2,
            node.bounds.min[1] + (node.bounds.max[1] - node.bounds.min[1]) / 2,
            node.bounds.min[2] + (node.bounds.max[2] - node.bounds.min[2]) / 2,
        ];
        let index = 0;
        if (point[0] >= mid[0]) index |= 1; if (point[1] >= mid[1]) index |= 2; if (point[2] >= mid[2]) index |= 4;
        return index;
    }
    insert(point, data) {
        let node = this.root;
        while (true) {
            if (node.depth === this.maxDepth) { node.data = data; return; }
            if (node.isLeaf) { node.subdivide(); }
            node = node.children[this._getChildIndex(point, node)];
        }
    }
    find(point) { /* ... implementation ... */ }
    remove(point) { this.insert(point, null); }

    // Flatten the Octree into a texture-friendly format (Float32Array)
    flattenToTexture(maxNodes) {
        const data = new Float32Array(maxNodes * 8);
        const queue = [{ node: this.root, index: 0 }];
        let head = 0;
        let tail = 1;

        while(head < tail && tail < maxNodes) {
            const { node, index } = queue[head++];
            const dataIndex = index * 8;

            if (node.isLeaf) {
                for(let i = 0; i < 7; i++) data[dataIndex + i] = 0;
                data[dataIndex + 7] = node.data || 0;
            } else {
                for (let i = 0; i < 8; i++) {
                    if (node.children[i]) {
                        data[dataIndex + i] = tail;
                        queue[tail++] = { node: node.children[i], index: tail };
                    } else {
                        data[dataIndex + i] = 0;
                    }
                }
            }
        }
        return data;
    }

    // Raycast against the Octree on the CPU
    raycast(ro, rd) {
        // Broad phase: intersect with the root bounding box
        let tmin = (this.root.bounds.min[0] - ro[0]) / rd[0];
        let tmax = (this.root.bounds.max[0] - ro[0]) / rd[0];
        if (tmin > tmax) [tmin, tmax] = [tmax, tmin];

        let tymin = (this.root.bounds.min[1] - ro[1]) / rd[1];
        let tymax = (this.root.bounds.max[1] - ro[1]) / rd[1];
        if (tymin > tymax) [tymin, tymax] = [tymax, tymin];

        if ((tmin > tymax) || (tymin > tmax)) return null;
        if (tymin > tmin) tmin = tymin;
        if (tymax < tmax) tmax = tymax;

        let tzmin = (this.root.bounds.min[2] - ro[2]) / rd[2];
        let tzmax = (this.root.bounds.max[2] - ro[2]) / rd[2];
        if (tzmin > tzmax) [tzmin, tzmax] = [tzmax, tzmin];

        if ((tmin > tzmax) || (tzmin > tmax)) return null;
        if (tzmin > tmin) tmin = tzmin;
        if (tzmax < tmax) tmax = tzmax;

        let t = tmin > 0 ? tmin : tmax;
        if (t < 0) return null;

        // Traverse the tree
        let node = this.root;
        while(t < 100.0) { // Max distance
            if (node.isLeaf) {
                if (node.data) {
                    const hitPos = [ro[0] + t*rd[0], ro[1] + t*rd[1], ro[2] + t*rd[2]];
                    const epsilon = 0.001;
                    const hitVoxel = [Math.floor(hitPos[0] - rd[0]*epsilon), Math.floor(hitPos[1] - rd[1]*epsilon), Math.floor(hitPos[2] - rd[2]*epsilon)];

                    // Calculate normal
                    const localPos = [hitPos[0] - hitVoxel[0] - 0.5, hitPos[1] - hitVoxel[1] - 0.5, hitPos[2] - hitVoxel[2] - 0.5];
                    const absLocalPos = localPos.map(Math.abs);
                    let normal = [0,0,0];
                    if (absLocalPos[0] > absLocalPos[1] && absLocalPos[0] > absLocalPos[2]) {
                        normal[0] = Math.sign(localPos[0]);
                    } else if (absLocalPos[1] > absLocalPos[2]) {
                        normal[1] = Math.sign(localPos[1]);
                    } else {
                        normal[2] = Math.sign(localPos[2]);
                    }
                    return { position: hitVoxel, normal: normal };
                }
                return null; // Hit empty leaf
            }

            const childIndex = this._getChildIndex([ro[0] + t*rd[0], ro[1] + t*rd[1], ro[2] + t*rd[2]], node);
            node = node.children[childIndex];
            t += 0.01; // Simple step, not accurate but works for now
        }
        return null;
    }

    // --- Serialization for IndexedDB ---
    serialize() {
        const data = [];
        function _serializeNode(node) {
            if (node.isLeaf) {
                if (node.data) {
                    return { d: node.data }; // 'd' for data
                }
                return null; // Don't store empty leaves
            }
            const children = [];
            let hasChildren = false;
            for (let i = 0; i < 8; i++) {
                const childData = _serializeNode(node.children[i]);
                if (childData) hasChildren = true;
                children.push(childData);
            }
            if (!hasChildren) return null; // Don't store nodes with only empty leaves
            return { c: children }; // 'c' for children
        }
        return JSON.stringify(_serializeNode(this.root));
    }

    static deserialize(jsonString, worldSize, maxDepth) {
        const octree = new Octree(worldSize, maxDepth);
        const data = JSON.parse(jsonString);

        function _deserializeNode(node, nodeData) {
            if (!nodeData) return;
            if (nodeData.d) {
                node.data = nodeData.d;
                return;
            }
            if (nodeData.c) {
                node.subdivide();
                for (let i = 0; i < 8; i++) {
                    if (nodeData.c[i]) {
                        _deserializeNode(node.children[i], nodeData.c[i]);
                    }
                }
            }
        }
        _deserializeNode(octree.root, data);
        return octree;
    }
}

// --- INDEXEDDB WRAPPER ---
const dbManager = {
    db: null,
    open() {
        return new Promise((resolve, reject) => {
            const request = indexedDB.open('VoxelDB', 1);
            request.onupgradeneeded = (e) => {
                this.db = e.target.result;
                if (!this.db.objectStoreNames.contains('worldData')) {
                    this.db.createObjectStore('worldData', { keyPath: 'id' });
                }
            };
            request.onsuccess = (e) => { this.db = e.target.result; resolve(); };
            request.onerror = (e) => reject('IndexedDB error: ' + e.target.errorCode);
        });
    },
    save(data) {
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction(['worldData'], 'readwrite');
            const store = transaction.objectStore('worldData');
            const request = store.put({ id: 'world', data: data });
            request.onsuccess = () => resolve();
            request.onerror = (e) => reject('Save error: ' + e.target.errorCode);
        });
    },
    load() {
        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction(['worldData'], 'readonly');
            const store = transaction.objectStore('worldData');
            const request = store.get('world');
            request.onsuccess = (e) => resolve(e.target.result ? e.target.result.data : null);
            request.onerror = (e) => reject('Load error: ' + e.target.errorCode);
        });
    }
};


// --- WEBGL AND APPLICATION LOGIC ---
async function main() {
    const canvas = document.getElementById('gl-canvas');
    const gl = canvas.getContext('webgl');
    if (!gl) { alert('WebGL not supported!'); return; }

    await dbManager.open();
    const savedWorld = await dbManager.load();

    const worldSize = 16;
    const maxDepth = 4;
    let octree;

    if (savedWorld) {
        octree = Octree.deserialize(savedWorld, worldSize, maxDepth);
        console.log("Loaded world from IndexedDB.");
    } else {
        octree = new Octree(worldSize, maxDepth);
        // Create a ground plane for new worlds
        for (let x = 0; x < worldSize; x++) {
            for (let z = 0; z < worldSize; z++) {
                octree.insert([x + 0.5, 0.5, z + 0.5], 1); // Dirt
            }
        }
        octree.insert([8.5, 1.5, 8.5], 2); // Stone block
        console.log("Created a new default world.");
    }

    const vsSource = await fetch('shaders/vertex.glsl').then(res => res.text());
    const fsSource = await fetch('shaders/fragment.glsl').then(res => res.text());
    const shaderProgram = initShaderProgram(gl, vsSource, fsSource);
    if (!shaderProgram) return;

    const programInfo = {
        program: shaderProgram,
        attribLocations: {
            vertexPosition: gl.getAttribLocation(shaderProgram, 'a_position'),
        },
        uniformLocations: {
            resolution: gl.getUniformLocation(shaderProgram, 'u_resolution'),
            cameraYaw: gl.getUniformLocation(shaderProgram, 'u_cameraYaw'),
            cameraPitch: gl.getUniformLocation(shaderProgram, 'u_cameraPitch'),
            cameraPos: gl.getUniformLocation(shaderProgram, 'u_cameraPos'),
            cameraForward: gl.getUniformLocation(shaderProgram, 'u_cameraForward'),
            cameraRight: gl.getUniformLocation(shaderProgram, 'u_cameraRight'),
            cameraUp: gl.getUniformLocation(shaderProgram, 'u_cameraUp'),
            octreeTexture: gl.getUniformLocation(shaderProgram, 'u_octreeTexture'),
            textureSize: gl.getUniformLocation(shaderProgram, 'u_textureSize'),
        },
    };

    const quadBuffer = initBuffers(gl);

    // Flatten octree and create texture
    const maxNodes = 8192; // Increased size for more complex worlds
    const octreeTextureData = octree.flattenToTexture(maxNodes);
    let octreeTexture = createDataTexture(gl, octreeTextureData, maxNodes, 2, maxNodes);

    let cameraPos = [worldSize / 2, worldSize / 2, -worldSize];
    let cameraYaw = 0.0;
    let cameraPitch = 0.0;
    let isDragging = false;
    let lastMouseX = 0;
    let lastMouseY = 0;

    let cameraForward = [0, 0, 1];
    let cameraRight = [1, 0, 0];
    let cameraUp = [0, 1, 0];


    function updateOctreeTexture() {
        octreeTextureData = octree.flattenToTexture(maxNodes);
        updateDataTexture(gl, octreeTexture, octreeTextureData, 2, maxNodes);
    }

    canvas.addEventListener('click', (e) => {
        if (e.target.id !== 'gl-canvas') return;

        const rect = canvas.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;

        const aspect = canvas.width / canvas.height;
        const uvx = (x / canvas.width * 2 - 1) * aspect;
        const uvy = y / canvas.height * -2 + 1;

        const fov = 1.5; // Matches shader
        const rd = normalize([
            uvx * cameraRight[0] + uvy * cameraUp[0] + fov * cameraForward[0],
            uvx * cameraRight[1] + uvy * cameraUp[1] + fov * cameraForward[1],
            uvx * cameraRight[2] + uvy * cameraUp[2] + fov * cameraForward[2]
        ]);

        const hit = octree.raycast(cameraPos, rd);

        if (hit) {
            if (e.button === 0) { // Left-click: Build
                const newVoxelPos = [
                    hit.position[0] + hit.normal[0] + 0.5,
                    hit.position[1] + hit.normal[1] + 0.5,
                    hit.position[2] + hit.normal[2] + 0.5,
                ];
                const voxelType = parseInt(document.getElementById('voxel-type').value, 10);
                octree.insert(newVoxelPos, voxelType);
            } else if (e.button === 2) { // Right-click: Dig
                const voxelToRemove = [hit.position[0] + 0.5, hit.position[1] + 0.5, hit.position[2] + 0.5];
                octree.remove(voxelToRemove);
            }
            updateOctreeTexture();
        }
    });

    document.getElementById('save-button').addEventListener('click', async () => {
        try {
            const serializedData = octree.serialize();
            await dbManager.save(serializedData);
            alert('World saved!');
        } catch (error) {
            console.error('Failed to save world:', error);
            alert('Error saving world. Check console for details.');
        }
    });

    canvas.addEventListener('mousedown', (e) => {
        isDragging = true;
        lastMouseX = e.clientX;
        lastMouseY = e.clientY;
    });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault()); // Prevent right-click menu
    canvas.addEventListener('mouseup', () => {
        setTimeout(()=> isDragging = false, 50); // Delay to differentiate click from drag
    });
    canvas.addEventListener('mousemove', (e) => {
        if (!isDragging || e.buttons === 0) {
             isDragging = false;
             return;
        }
        const dx = e.clientX - lastMouseX;
        const dy = e.clientY - lastMouseY;
        cameraYaw -= dx * 0.005;
        cameraPitch -= dy * 0.005;
        cameraPitch = Math.max(-Math.PI / 2, Math.min(Math.PI / 2, cameraPitch)); // Clamp pitch
        lastMouseX = e.clientX;
        lastMouseY = e.clientY;
    });

    function render() {
        resizeCanvasToDisplaySize(gl.canvas);
        gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);
        gl.clearColor(0.0, 0.0, 0.0, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        // Calculate camera vectors
        const cy = Math.cos(cameraYaw);
        const sy = Math.sin(cameraYaw);
        const cp = Math.cos(cameraPitch);
        const sp = Math.sin(cameraPitch);

        cameraForward = [-sy * cp, sp, -cy * cp];
        cameraRight = [cy, 0, -sy];
        cameraUp = cross(cameraForward, cameraRight);

        gl.useProgram(programInfo.program);
        gl.uniform2f(programInfo.uniformLocations.resolution, gl.canvas.width, gl.canvas.height);
        gl.uniform3fv(programInfo.uniformLocations.cameraPos, cameraPos);
        gl.uniform3fv(programInfo.uniformLocations.cameraForward, cameraForward);
        gl.uniform3fv(programInfo.uniformLocations.cameraRight, cameraRight);
        gl.uniform3fv(programInfo.uniformLocations.cameraUp, cameraUp);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, octreeTexture);
        gl.uniform1i(programInfo.uniformLocations.octreeTexture, 0);
        gl.uniform1f(programInfo.uniformLocations.textureSize, maxNodes);


        gl.bindBuffer(gl.ARRAY_BUFFER, quadBuffer);
        gl.vertexAttribPointer(programInfo.attribLocations.vertexPosition, 2, gl.FLOAT, false, 0, 0);
        gl.enableVertexAttribArray(programInfo.attribLocations.vertexPosition);

        gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

        requestAnimationFrame(render);
    }
    requestAnimationFrame(render);
}

function createDataTexture(gl, data, width, height) {
    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.FLOAT, data);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return texture;
}

function updateDataTexture(gl, texture, data, width, height) {
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, width, height, gl.RGBA, gl.FLOAT, data);
}

// --- VECTOR MATH HELPERS ---
function normalize(v) {
    const len = Math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
    return [v[0]/len, v[1]/len, v[2]/len];
}
function cross(a, b) {
    return [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0]
    ];
}


function initBuffers(gl) {
    const positionBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
    const positions = [-1.0, 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, -1.0];
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(positions), gl.STATIC_DRAW);
    return positionBuffer;
}

function initShaderProgram(gl, vsSource, fsSource) {
    const vertexShader = loadShader(gl, gl.VERTEX_SHADER, vsSource);
    const fragmentShader = loadShader(gl, gl.FRAGMENT_SHADER, fsSource);
    const shaderProgram = gl.createProgram();
    gl.attachShader(shaderProgram, vertexShader);
    gl.attachShader(shaderProgram, fragmentShader);
    gl.linkProgram(shaderProgram);
    if (!gl.getProgramParameter(shaderProgram, gl.LINK_STATUS)) {
        alert('Unable to initialize the shader program: ' + gl.getProgramInfoLog(shaderProgram));
        return null;
    }
    return shaderProgram;
}

function loadShader(gl, type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        alert('An error occurred compiling the shaders: ' + gl.getShaderInfoLog(shader));
        gl.deleteShader(shader);
        return null;
    }
    return shader;
}

function resizeCanvasToDisplaySize(canvas) {
    const displayWidth = canvas.clientWidth;
    const displayHeight = canvas.clientHeight;
    if (canvas.width !== displayWidth || canvas.height !== displayHeight) {
        canvas.width = displayWidth;
        canvas.height = displayHeight;
        return true;
    }
    return false;
}

main();