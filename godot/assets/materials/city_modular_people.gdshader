shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// One topology/material for all forty appearances. GPU instance data selects
// the roster; no race or appearance code runs in the gameplay update loop.
uniform vec4 skin_palette[40];
uniform vec4 top_palette[40];
uniform vec4 pants_palette[40];
uniform vec4 hair_palette[40];
uniform vec4 shoe_palette[40];
uniform vec4 accent_palette[40];
uniform vec4 proportions[40]; // width, depth, face width, height / 1.7
uniform vec4 features[40]; // hair, garment, beard, reserved
uniform vec4 face_shapes[40]; // jaw width, nose width, nose projection, eye spacing
uniform vec4 face_details[40]; // eye height, lip width, chin length, reserved
uniform vec4 hair_shapes[40]; // width, height, depth, reserved
uniform vec4 tailoring[40]; // waist, shoulder, trouser width, reserved
instance uniform int roster_override = -1;
instance uniform bool rigged = false;
uniform float crowd_clock = 0.0;
varying vec3 appearance_color;

mat3 turn_x(float a) {
    float c = cos(a); float s = sin(a);
    return mat3(vec3(1.0,0.0,0.0), vec3(0.0,c,s), vec3(0.0,-s,c));
}
mat3 turn_y(float a) {
    float c = cos(a); float s = sin(a);
    return mat3(vec3(c,0.0,-s), vec3(0.0,1.0,0.0), vec3(s,0.0,c));
}
mat3 turn_z(float a) {
    float c = cos(a); float s = sin(a);
    return mat3(vec3(c,s,0.0), vec3(-s,c,0.0), vec3(0.0,0.0,1.0));
}

void vertex() {
    int person = clamp(roster_override >= 0 ? roster_override : int(INSTANCE_CUSTOM.r + 0.5), 0, 39);
    int component = int(UV2.x + 0.5);
    int idle = rigged ? 0 : int(INSTANCE_CUSTOM.g + 0.5);
    int part = int(UV.y + 0.5);
    float near_weight = 0.0;
    if (!rigged && idle > 0) {
        near_weight = 1.0 - smoothstep(25.0, 32.0, distance(INV_VIEW_MATRIX[3].xyz, MODEL_MATRIX[3].xyz));
    }
    if (near_weight <= 0.0) { idle = 0; }
    bool shown = true;
    if (component >= 1 && component <= 12) { shown = component == int(features[person].x) + 1; }
    if (component >= 20 && component <= 28) { shown = component == int(features[person].y) + 20; }
    if (component == 29) { int garment = int(features[person].y); shown = garment == 1 || garment == 3 || garment == 4 || garment == 6; }
    if (component == 40) { shown = features[person].z > 0.5; }
    if (component == 50) { shown = idle == 2; }
    if (component == 51) { shown = idle == 3; }
    if (!shown) { VERTEX = vec3(0.0); }
    else {
        // Authored-space morphs are evaluated before articulation. Rig vertices
        // are pivot-local; seated crowd heads are lowered 31cm by the mesh cache.
        // Restore that offset for fitting, then return to the original frame.
        if (UV2.y > 0.5) {
            vec3 origin = vec3(0.0);
            if (rigged) { origin = component == 64 ? vec3(0.0,1.465,0.147) : vec3(0.0,1.37,0.0); }
            else if (part == 0) { origin.y = 0.31; }
            vec3 face = VERTEX + origin;
            if (component >= 1 && component <= 12) {
                vec3 hair_scale = mix(vec3(1.0), hair_shapes[person].xyz, smoothstep(1.625,1.68,face.y));
                face = vec3(0.0,1.60,-0.02) + (face - vec3(0.0,1.60,-0.02)) * hair_scale;
                NORMAL = normalize(NORMAL / hair_scale);
            } else {
                float jaw = mix(face_shapes[person].x, 1.0, smoothstep(1.40,1.53,face.y));
                face.x *= jaw;
                NORMAL.x /= jaw;
                float chin = 1.0 - smoothstep(1.39,1.47,face.y);
                face.y -= (face_details[person].z - 1.0) * 0.045 * chin;
                if (component == 60) {
                    face.x *= face_shapes[person].y;
                    face.z = 0.110 + (face.z - 0.110) * face_shapes[person].z;
                    NORMAL /= vec3(face_shapes[person].y,1.0,face_shapes[person].z);
                }
                if (component == 61 || component == 62) {
                    face.x *= face_shapes[person].w;
                    face.y += face_details[person].x;
                }
                if (component == 64) { face.x *= face_details[person].y; }
            }
            face.x *= proportions[person].z;
            NORMAL.x /= proportions[person].z;
            NORMAL = normalize(NORMAL);
            VERTEX = face - origin;
        }
        // Fitted waist/shoulder shaping stays inside the original arm pivots.
        if (UV2.y < -0.5 && UV2.y > -1.5) {
            float body_y = VERTEX.y + (rigged ? 0.81 : (part == 0 ? 0.31 : 0.0));
            float fit = mix(tailoring[person].x, tailoring[person].y, smoothstep(0.90,1.29,body_y));
            if (int(UV.x + 0.5) != 11) { VERTEX.x *= fit; NORMAL.x /= fit; NORMAL = normalize(NORMAL); }
        }
        if (UV2.y < -1.5 && UV2.y > -2.5) {
            float leg_center = rigged ? 0.0 : (VERTEX.x < 0.0 ? -0.115 : 0.115);
            VERTEX.x = leg_center + (VERTEX.x - leg_center) * tailoring[person].z;
            NORMAL.x /= tailoring[person].z;
            NORMAL = normalize(NORMAL);
        }
        if (!rigged && idle > 0 && part > 0) {
            float phase = INSTANCE_CUSTOM.b * 6.2831853;
            float t = crowd_clock;
            float breath = sin(t * 1.35 + phase) * 0.007 * near_weight;
            if (part == 2) {
                mat3 look = turn_y(sin(t * 0.43 + phase) * 0.08 * near_weight);
                VERTEX = vec3(0.0,1.37,0.0) + look * (VERTEX - vec3(0.0,1.37,0.0));
                NORMAL = look * NORMAL;
            }
            if (part == 3 || part == 4 || part == 7) {
                bool right_arm = part != 4;
                vec3 shoulder = vec3(right_arm ? -0.265 : 0.265,1.31,0.0);
                float gesture = 0.0;
                if (right_arm && (idle == 2 || idle == 3)) {
                    float cycle = mod(t + INSTANCE_CUSTOM.b * 19.0, idle == 2 ? 14.0 : 19.0);
                    gesture = smoothstep(1.0,2.4,cycle) * (1.0 - smoothstep(4.2,6.0,cycle)) * near_weight;
                }
                float relaxed = sin(t * 0.71 + phase + (right_arm ? 0.0 : 1.4)) * 0.045;
                if (idle == 4) { relaxed = sin(t * 6.0 + phase) * (right_arm ? 0.20 : -0.20); }
                mat3 arm = turn_x(relaxed * near_weight);
                float elbow_angle = 0.0;
                if (gesture > 0.0) {
                    // Offline endpoint fit: peak hand reaches the mouth, while
                    // the elbow stays in front of the chest rather than at the ear.
                    vec3 angles = idle == 2 ? vec3(-1.9385,0.455657,-0.880661) : vec3(-1.8476,0.5236,-0.689814);
                    arm = turn_z(angles.z * gesture) * turn_y(angles.y * gesture)
                        * turn_x(angles.x * gesture + relaxed * (1.0 - gesture) * near_weight);
                    elbow_angle = (idle == 2 ? -1.604516 : -1.144234) * gesture;
                }
                vec3 elbow_pivot = vec3(-0.285,1.06,0.015);
                if (part == 7) {
                    // Independent wrist articulation keeps the cigarette pointing
                    // away from the lips and tips the bottle neck toward them.
                    vec3 hand = vec3(-0.285,0.86,0.025);
                    vec3 posed_hand = shoulder + arm * (elbow_pivot + turn_x(elbow_angle) * (hand - elbow_pivot) - shoulder);
                    mat3 wrist = arm;
                    if (gesture > 0.0) {
                        wrist = turn_x((idle == 3 ? -1.85 : 0.0) * gesture + relaxed * (1.0 - gesture) * near_weight);
                    }
                    VERTEX = posed_hand + wrist * (VERTEX - hand);
                    NORMAL = wrist * NORMAL;
                } else {
                    float elbow_weight = right_arm ? 1.0 - smoothstep(1.035,1.075,VERTEX.y) : 0.0;
                    mat3 elbow = turn_x(elbow_angle * elbow_weight);
                    VERTEX = elbow_pivot + elbow * (VERTEX - elbow_pivot);
                    VERTEX = shoulder + arm * (VERTEX - shoulder);
                    NORMAL = arm * elbow * NORMAL;
                }
            }
            if (idle == 4 && (part == 5 || part == 6)) {
                vec3 hip = vec3(part == 5 ? -0.115 : 0.115,0.81,0.0);
                mat3 leg_turn = turn_x(sin(t * 6.0 + phase) * (part == 5 ? 0.18 : -0.18) * near_weight);
                VERTEX = hip + leg_turn * (VERTEX - hip);
                NORMAL = leg_turn * NORMAL;
            }
            if (part == 1 || part == 2 || part == 3 || part == 4 || part == 7) { VERTEX.y += breath; }
        }
        if (!rigged) {
            VERTEX *= vec3(proportions[person].x, proportions[person].w, proportions[person].y);
            NORMAL = normalize(NORMAL / vec3(proportions[person].x, proportions[person].w, proportions[person].y));
        }
    }
    int slot = int(UV.x + 0.5);
    vec3 skin = skin_palette[person].rgb;
    vec3 top = top_palette[person].rgb;
    appearance_color = skin;
    if (slot == 1) {
        appearance_color = top;
        if ((int(features[person].y) == 6 || int(features[person].y) == 7) && UV2.y < -2.5) { appearance_color = accent_palette[person].rgb; }
    }
    if (slot == 2) { appearance_color = pants_palette[person].rgb; }
    if (slot == 3) { appearance_color = hair_palette[person].rgb; }
    if (slot == 4) { appearance_color = shoe_palette[person].rgb; }
    if (slot == 5) { appearance_color = vec3(0.84, 0.82, 0.76); }
    if (slot == 6) { appearance_color = vec3(0.022, 0.014, 0.009); }
    if (slot == 7) { appearance_color = skin * vec3(0.72, 0.49, 0.49); }
    if (slot == 8) { appearance_color = accent_palette[person].rgb; }
    if (slot == 9) { appearance_color = top * 0.64; }
    if (slot == 10) { appearance_color = vec3(0.009, 0.008, 0.008); }
    if (slot == 11) { appearance_color = vec3(0.18, 0.12, 0.07); }
    if (slot == 12) { appearance_color = vec3(0.42, 0.40, 0.35); }
    if (slot == 13) { appearance_color = vec3(0.38, 0.22, 0.09); }
    if (slot == 14) { appearance_color = vec3(0.06, 0.13, 0.055); }
    if (slot == 15) { appearance_color = vec3(0.75, 0.15, 0.025); }
}

void fragment() {
    ALBEDO = appearance_color;
    // Smooth color fields without procedural grain; controlled finish by region.
    int slot = int(UV.x + 0.5);
    ROUGHNESS = slot == 0 ? 0.72 : (slot == 3 ? 0.78 : (slot == 4 ? 0.68 : 0.86));
    SPECULAR = 0.24;
}
