#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <ctype.h>
#include <stdarg.h>

static int _argc; static char** _argv;

typedef struct ABlock { struct ABlock* next; int cap; int used; } ABlock;
static ABlock* _arena = 0;
static char* _alloc(int n) {
    n = (n + 7) & ~7;
    if (!_arena || _arena->used + n > _arena->cap) {
        int cap = 64*1024*1024;
        if (n > cap) cap = n;
        ABlock* b = (ABlock*)malloc(sizeof(ABlock) + cap);
        if (!b) { fprintf(stderr, "out of memory\n"); exit(1); }
        b->cap = cap; b->used = 0; b->next = _arena; _arena = b;
    }
    char* p = (char*)(_arena + 1) + _arena->used;
    _arena->used += n;
    return p;
}

static char _K_EMPTY[] = "";
static char _K_ZERO[] = "0";
static char _K_ONE[] = "1";

static char* kr_str(const char* s) {
    if (!s[0]) return _K_EMPTY;
    if (s[0] == '0' && !s[1]) return _K_ZERO;
    if (s[0] == '1' && !s[1]) return _K_ONE;
    int n = (int)strlen(s) + 1;
    char* p = _alloc(n);
    memcpy(p, s, n);
    return p;
}

static char* kr_cat(const char* a, const char* b) {
    int la = (int)strlen(a), lb = (int)strlen(b);
    char* p = _alloc(la + lb + 1);
    memcpy(p, a, la);
    memcpy(p + la, b, lb + 1);
    return p;
}

static int kr_isnum(const char* s) {
    if (!*s) return 0;
    const char* p = s;
    if (*p == '-') p++;
    if (!*p) return 0;
    while (*p) { if (*p < '0' || *p > '9') return 0; p++; }
    return 1;
}

static char* kr_itoa(int v) {
    if (v == 0) return _K_ZERO;
    if (v == 1) return _K_ONE;
    char buf[32];
    snprintf(buf, sizeof(buf), "%d", v);
    return kr_str(buf);
}

static int kr_atoi(const char* s) { return atoi(s); }

static char* kr_plus(const char* a, const char* b) {
    if (kr_isnum(a) && kr_isnum(b))
        return kr_itoa(atoi(a) + atoi(b));
    return kr_cat(a, b);
}

static char* kr_sub(const char* a, const char* b) { return kr_itoa(atoi(a) - atoi(b)); }
static char* kr_mul(const char* a, const char* b) { return kr_itoa(atoi(a) * atoi(b)); }
static char* kr_div(const char* a, const char* b) { return kr_itoa(atoi(a) / atoi(b)); }
static char* kr_mod(const char* a, const char* b) { return kr_itoa(atoi(a) % atoi(b)); }
static char* kr_neg(const char* a) { return kr_itoa(-atoi(a)); }
static char* kr_not(const char* a) { return atoi(a) ? _K_ZERO : _K_ONE; }

static char* kr_eq(const char* a, const char* b) {
    return strcmp(a, b) == 0 ? _K_ONE : _K_ZERO;
}
static char* kr_neq(const char* a, const char* b) {
    return strcmp(a, b) != 0 ? _K_ONE : _K_ZERO;
}
static char* kr_lt(const char* a, const char* b) {
    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) < atoi(b) ? _K_ONE : _K_ZERO;
    return strcmp(a, b) < 0 ? _K_ONE : _K_ZERO;
}
static char* kr_gt(const char* a, const char* b) {
    if (kr_isnum(a) && kr_isnum(b)) return atoi(a) > atoi(b) ? _K_ONE : _K_ZERO;
    return strcmp(a, b) > 0 ? _K_ONE : _K_ZERO;
}
static char* kr_lte(const char* a, const char* b) {
    return kr_gt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;
}
static char* kr_gte(const char* a, const char* b) {
    return kr_lt(a, b) == _K_ZERO ? _K_ONE : _K_ZERO;
}

static int kr_truthy(const char* s) {
    if (!s || !*s) return 0;
    if (strcmp(s, "0") == 0) return 0;
    return 1;
}

static char* kr_print(const char* s) {
    printf("%s\n", s);
    return _K_EMPTY;
}

static char* kr_len(const char* s) { return kr_itoa((int)strlen(s)); }

static char* kr_idx(const char* s, int i) {
    char buf[2] = {s[i], 0};
    return kr_str(buf);
}

static char* kr_split(const char* s, const char* idxs) {
    int idx = atoi(idxs);
    int count = 0;
    const char* start = s;
    const char* p = s;
    while (*p) {
        if (*p == ',') {
            if (count == idx) {
                int len = (int)(p - start);
                char* r = _alloc(len + 1);
                memcpy(r, start, len);
                r[len] = 0;
                return r;
            }
            count++;
            start = p + 1;
        }
        p++;
    }
    if (count == idx) return kr_str(start);
    return kr_str("");
}

static char* kr_startswith(const char* s, const char* prefix) {
    return strncmp(s, prefix, strlen(prefix)) == 0 ? _K_ONE : _K_ZERO;
}

static char* kr_substr(const char* s, const char* starts, const char* ends) {
    int st = atoi(starts), en = atoi(ends);
    int slen = (int)strlen(s);
    if (st >= slen) return kr_str("");
    if (en > slen) en = slen;
    int n = en - st;
    if (n <= 0) return kr_str("");
    char* r = _alloc(n + 1);
    memcpy(r, s + st, n);
    r[n] = 0;
    return r;
}

static char* kr_toint(const char* s) { return kr_itoa(atoi(s)); }

static char* kr_readfile(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) return kr_str("");
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = _alloc((int)sz + 1);
    fread(buf, 1, sz, f);
    buf[sz] = 0;
    fclose(f);
    return buf;
}

static char* kr_arg(const char* idxs) {
    int idx = atoi(idxs) + 1;
    if (idx < _argc) return kr_str(_argv[idx]);
    return kr_str("");
}

static char* kr_argcount() {
    return kr_itoa(_argc - 1);
}

static char* kr_getline(const char* s, const char* idxs) {
    int idx = atoi(idxs);
    int cur = 0;
    const char* start = s;
    const char* p = s;
    while (*p) {
        if (*p == '\n') {
            if (cur == idx) {
                int len = (int)(p - start);
                char* r = _alloc(len + 1);
                memcpy(r, start, len);
                r[len] = 0;
                return r;
            }
            cur++;
            start = p + 1;
        }
        p++;
    }
    if (cur == idx) return kr_str(start);
    return kr_str("");
}

static char* kr_linecount(const char* s) {
    if (!*s) return kr_str("0");
    int count = 1;
    const char* p = s;
    while (*p) { if (*p == '\n') count++; p++; }
    if (*(p - 1) == '\n') count--;
    return kr_itoa(count);
}

static char* kr_count(const char* s) {
    return kr_linecount(s);
}

static char* kr_writefile(const char* path, const char* data) {
    FILE* f = fopen(path, "wb");
    if (!f) return _K_ZERO;
    fwrite(data, 1, strlen(data), f);
    fclose(f);
    return _K_ONE;
}

static char* kr_input() {
    char buf[4096];
    if (!fgets(buf, sizeof(buf), stdin)) return _K_EMPTY;
    int len = (int)strlen(buf);
    if (len > 0 && buf[len-1] == '\n') buf[--len] = 0;
    if (len > 0 && buf[len-1] == '\r') buf[--len] = 0;
    return kr_str(buf);
}

static char* kr_indexof(const char* s, const char* sub) {
    const char* p = strstr(s, sub);
    if (!p) return kr_itoa(-1);
    return kr_itoa((int)(p - s));
}

static char* kr_replace(const char* s, const char* old, const char* rep) {
    int slen = (int)strlen(s), olen = (int)strlen(old), rlen = (int)strlen(rep);
    if (olen == 0) return kr_str(s);
    int count = 0;
    const char* p = s;
    while ((p = strstr(p, old)) != 0) { count++; p += olen; }
    int nlen = slen + count * (rlen - olen);
    char* out = _alloc(nlen + 1);
    char* dst = out;
    p = s;
    while (*p) {
        if (strncmp(p, old, olen) == 0) {
            memcpy(dst, rep, rlen); dst += rlen; p += olen;
        } else { *dst++ = *p++; }
    }
    *dst = 0;
    return out;
}

static char* kr_charat(const char* s, const char* idxs) {
    int i = atoi(idxs);
    int slen = (int)strlen(s);
    if (i < 0 || i >= slen) return _K_EMPTY;
    char buf[2] = {s[i], 0};
    return kr_str(buf);
}

static char* kr_trim(const char* s) {
    while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r') s++;
    int len = (int)strlen(s);
    while (len > 0 && (s[len-1]==' '||s[len-1]=='\t'||s[len-1]=='\n'||s[len-1]=='\r')) len--;
    char* r = _alloc(len + 1);
    memcpy(r, s, len);
    r[len] = 0;
    return r;
}

static char* kr_tolower(const char* s) {
    int len = (int)strlen(s);
    char* out = _alloc(len + 1);
    for (int i = 0; i <= len; i++)
        out[i] = (s[i] >= 'A' && s[i] <= 'Z') ? s[i] + 32 : s[i];
    return out;
}

static char* kr_toupper(const char* s) {
    int len = (int)strlen(s);
    char* out = _alloc(len + 1);
    for (int i = 0; i <= len; i++)
        out[i] = (s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i];
    return out;
}

static char* kr_contains(const char* s, const char* sub) {
    return strstr(s, sub) ? _K_ONE : _K_ZERO;
}

static char* kr_endswith(const char* s, const char* suffix) {
    int slen = (int)strlen(s), suflen = (int)strlen(suffix);
    if (suflen > slen) return _K_ZERO;
    return strcmp(s + slen - suflen, suffix) == 0 ? _K_ONE : _K_ZERO;
}

static char* kr_abs(const char* a) { int v = atoi(a); return kr_itoa(v < 0 ? -v : v); }
static char* kr_min(const char* a, const char* b) { return atoi(a) <= atoi(b) ? kr_str(a) : kr_str(b); }
static char* kr_max(const char* a, const char* b) { return atoi(a) >= atoi(b) ? kr_str(a) : kr_str(b); }

static char* kr_exit(const char* code) { exit(atoi(code)); return _K_EMPTY; }

static char* kr_type(const char* s) {
    if (kr_isnum(s)) return kr_str("number");
    return kr_str("string");
}

static char* kr_append(const char* lst, const char* item) {
    if (!*lst) return kr_str(item);
    return kr_cat(kr_cat(lst, ","), item);
}

static char* kr_join(const char* lst, const char* sep) {
    int llen = (int)strlen(lst), slen = (int)strlen(sep);
    int rlen = 0;
    for (int i = 0; i < llen; i++) {
        if (lst[i] == ',') rlen += slen; else rlen++;
    }
    char* out = _alloc(rlen + 1);
    int j = 0;
    for (int i = 0; i < llen; i++) {
        if (lst[i] == ',') { memcpy(out+j, sep, slen); j += slen; }
        else { out[j++] = lst[i]; }
    }
    out[j] = 0;
    return out;
}

static char* kr_reverse(const char* lst) {
    int cnt = 0;
    const char* p = lst;
    while (*p) { if (*p == ',') cnt++; p++; }
    cnt++;
    char* out = _K_EMPTY;
    for (int i = cnt - 1; i >= 0; i--) {
        char* item = kr_split(lst, kr_itoa(i));
        if (i == cnt - 1) out = item;
        else out = kr_cat(kr_cat(out, ","), item);
    }
    return out;
}

static int _kr_cmp(const void* a, const void* b) {
    const char* sa = *(const char**)a;
    const char* sb = *(const char**)b;
    if (kr_isnum(sa) && kr_isnum(sb)) return atoi(sa) - atoi(sb);
    return strcmp(sa, sb);
}
static char* kr_sort(const char* lst) {
    if (!*lst) return _K_EMPTY;
    int cnt = 1;
    const char* p = lst;
    while (*p) { if (*p == ',') cnt++; p++; }
    char** arr = (char**)_alloc(cnt * sizeof(char*));
    for (int i = 0; i < cnt; i++) arr[i] = kr_split(lst, kr_itoa(i));
    qsort(arr, cnt, sizeof(char*), _kr_cmp);
    char* out = arr[0];
    for (int i = 1; i < cnt; i++) out = kr_cat(kr_cat(out, ","), arr[i]);
    return out;
}

static char* kr_keys(const char* map) {
    if (!*map) return _K_EMPTY;
    int cnt = 1;
    const char* p = map;
    while (*p) { if (*p == ',') cnt++; p++; }
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i += 2) {
        char* k = kr_split(map, kr_itoa(i));
        if (first) { out = k; first = 0; }
        else out = kr_cat(kr_cat(out, ","), k);
    }
    return out;
}

static char* kr_values(const char* map) {
    if (!*map) return _K_EMPTY;
    int cnt = 1;
    const char* p = map;
    while (*p) { if (*p == ',') cnt++; p++; }
    char* out = _K_EMPTY; int first = 1;
    for (int i = 1; i < cnt; i += 2) {
        char* v = kr_split(map, kr_itoa(i));
        if (first) { out = v; first = 0; }
        else out = kr_cat(kr_cat(out, ","), v);
    }
    return out;
}

static char* kr_haskey(const char* map, const char* key) {
    if (!*map) return _K_ZERO;
    int cnt = 1;
    const char* p = map;
    while (*p) { if (*p == ',') cnt++; p++; }
    for (int i = 0; i < cnt; i += 2) {
        if (strcmp(kr_split(map, kr_itoa(i)), key) == 0) return _K_ONE;
    }
    return _K_ZERO;
}

static char* kr_remove(const char* lst, const char* item) {
    if (!*lst) return _K_EMPTY;
    int cnt = 1;
    const char* p = lst;
    while (*p) { if (*p == ',') cnt++; p++; }
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i++) {
        char* el = kr_split(lst, kr_itoa(i));
        if (strcmp(el, item) != 0) {
            if (first) { out = el; first = 0; }
            else out = kr_cat(kr_cat(out, ","), el);
        }
    }
    return out;
}

static char* kr_repeat(const char* s, const char* ns) {
    int n = atoi(ns);
    if (n <= 0) return _K_EMPTY;
    int slen = (int)strlen(s);
    char* out = _alloc(slen * n + 1);
    for (int i = 0; i < n; i++) memcpy(out + i * slen, s, slen);
    out[slen * n] = 0;
    return out;
}

static char* kr_format(const char* fmt, const char* arg) {
    char buf[4096];
    const char* p = strstr(fmt, "{}");
    if (!p) return kr_str(fmt);
    int pre = (int)(p - fmt);
    int alen = (int)strlen(arg);
    int postlen = (int)strlen(p + 2);
    if (pre + alen + postlen >= 4096) return kr_str(fmt);
    memcpy(buf, fmt, pre);
    memcpy(buf + pre, arg, alen);
    memcpy(buf + pre + alen, p + 2, postlen + 1);
    return kr_str(buf);
}

static char* kr_parseint(const char* s) {
    const char* p = s;
    while (*p == ' ' || *p == '\t') p++;
    if (!*p) return _K_ZERO;
    return kr_itoa(atoi(p));
}

static char* kr_tostr(const char* s) { return kr_str(s); }

static int kr_listlen(const char* s) {
    if (!*s) return 0;
    int cnt = 1;
    while (*s) { if (*s == ',') cnt++; s++; }
    return cnt;
}

static char* kr_range(const char* starts, const char* ends) {
    int s = atoi(starts), e = atoi(ends);
    if (s >= e) return _K_EMPTY;
    char* out = kr_itoa(s);
    for (int i = s + 1; i < e; i++) out = kr_cat(kr_cat(out, ","), kr_itoa(i));
    return out;
}

static char* kr_pow(const char* bs, const char* es) {
    int b = atoi(bs), e = atoi(es), r = 1;
    for (int i = 0; i < e; i++) r *= b;
    return kr_itoa(r);
}

static char* kr_sqrt(const char* s) {
    int v = atoi(s);
    if (v <= 0) return _K_ZERO;
    int r = 0;
    while ((r + 1) * (r + 1) <= v) r++;
    return kr_itoa(r);
}

static char* kr_sign(const char* s) {
    int v = atoi(s);
    if (v > 0) return _K_ONE;
    if (v < 0) return kr_str("-1");
    return _K_ZERO;
}

static char* kr_clamp(const char* vs, const char* los, const char* his) {
    int v = atoi(vs), lo = atoi(los), hi = atoi(his);
    if (v < lo) return kr_str(los);
    if (v > hi) return kr_str(his);
    return kr_str(vs);
}

static char* kr_padleft(const char* s, const char* ws, const char* pad) {
    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);
    if (slen >= w || plen == 0) return kr_str(s);
    int need = w - slen;
    char* out = _alloc(w + 1);
    for (int i = 0; i < need; i++) out[i] = pad[i % plen];
    memcpy(out + need, s, slen + 1);
    return out;
}

static char* kr_padright(const char* s, const char* ws, const char* pad) {
    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);
    if (slen >= w || plen == 0) return kr_str(s);
    int need = w - slen;
    char* out = _alloc(w + 1);
    memcpy(out, s, slen);
    for (int i = 0; i < need; i++) out[slen + i] = pad[i % plen];
    out[w] = 0;
    return out;
}

static char* kr_charcode(const char* s) {
    if (!*s) return _K_ZERO;
    return kr_itoa((unsigned char)s[0]);
}

static char* kr_fromcharcode(const char* ns) {
    char buf[2] = {(char)atoi(ns), 0};
    return kr_str(buf);
}

static char* kr_slice(const char* lst, const char* starts, const char* ends) {
    int cnt = kr_listlen(lst);
    int s = atoi(starts), e = atoi(ends);
    if (s < 0) s = cnt + s;
    if (e < 0) e = cnt + e;
    if (s < 0) s = 0;
    if (e > cnt) e = cnt;
    if (s >= e) return _K_EMPTY;
    char* out = kr_split(lst, kr_itoa(s));
    for (int i = s + 1; i < e; i++)
        out = kr_cat(kr_cat(out, ","), kr_split(lst, kr_itoa(i)));
    return out;
}

static char* kr_length(const char* lst) {
    return kr_itoa(kr_listlen(lst));
}

static char* kr_unique(const char* lst) {
    if (!*lst) return _K_EMPTY;
    int cnt = kr_listlen(lst);
    char* out = _K_EMPTY; int oc = 0;
    for (int i = 0; i < cnt; i++) {
        char* item = kr_split(lst, kr_itoa(i));
        int dup = 0;
        for (int j = 0; j < oc; j++) {
            if (strcmp(kr_split(out, kr_itoa(j)), item) == 0) { dup = 1; break; }
        }
        if (!dup) {
            if (oc == 0) out = item; else out = kr_cat(kr_cat(out, ","), item);
            oc++;
        }
    }
    return out;
}

static char* kr_printerr(const char* s) {
    fprintf(stderr, "%s\n", s);
    return _K_EMPTY;
}

static char* kr_readline(const char* prompt) {
    if (*prompt) printf("%s", prompt);
    fflush(stdout);
    char buf[4096];
    if (!fgets(buf, sizeof(buf), stdin)) return _K_EMPTY;
    int len = (int)strlen(buf);
    if (len > 0 && buf[len-1] == '\n') buf[--len] = 0;
    if (len > 0 && buf[len-1] == '\r') buf[--len] = 0;
    return kr_str(buf);
}

static char* kr_assert(const char* cond, const char* msg) {
    if (!kr_truthy(cond)) {
        fprintf(stderr, "ASSERTION FAILED: %s\n", msg);
        exit(1);
    }
    return _K_ONE;
}

static char* kr_splitby(const char* s, const char* delim) {
    int slen = (int)strlen(s), dlen = (int)strlen(delim);
    if (dlen == 0 || slen == 0) return kr_str(s);
    char* out = _K_EMPTY; int first = 1;
    const char* p = s;
    while (*p) {
        const char* f = strstr(p, delim);
        if (!f) { 
            if (first) out = kr_str(p); else out = kr_cat(kr_cat(out, ","), kr_str(p));
            break;
        }
        int n = (int)(f - p);
        char* chunk = _alloc(n + 1);
        memcpy(chunk, p, n); chunk[n] = 0;
        if (first) { out = chunk; first = 0; }
        else out = kr_cat(kr_cat(out, ","), chunk);
        p = f + dlen;
        if (!*p) { out = kr_cat(kr_cat(out, ","), _K_EMPTY); break; }
    }
    return out;
}

static char* kr_listindexof(const char* lst, const char* item) {
    if (!*lst) return kr_itoa(-1);
    int cnt = kr_listlen(lst);
    for (int i = 0; i < cnt; i++) {
        if (strcmp(kr_split(lst, kr_itoa(i)), item) == 0) return kr_itoa(i);
    }
    return kr_itoa(-1);
}

static char* kr_insertat(const char* lst, const char* idxs, const char* item) {
    int idx = atoi(idxs);
    int cnt = kr_listlen(lst);
    if (!*lst && idx == 0) return kr_str(item);
    if (idx < 0) idx = 0;
    if (idx >= cnt) return kr_cat(kr_cat(lst, ","), item);
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i++) {
        if (i == idx) {
            if (first) { out = kr_str(item); first = 0; }
            else out = kr_cat(kr_cat(out, ","), item);
        }
        char* el = kr_split(lst, kr_itoa(i));
        if (first) { out = el; first = 0; }
        else out = kr_cat(kr_cat(out, ","), el);
    }
    return out;
}

static char* kr_removeat(const char* lst, const char* idxs) {
    int idx = atoi(idxs);
    int cnt = kr_listlen(lst);
    if (idx < 0 || idx >= cnt) return kr_str(lst);
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i++) {
        if (i == idx) continue;
        char* el = kr_split(lst, kr_itoa(i));
        if (first) { out = el; first = 0; }
        else out = kr_cat(kr_cat(out, ","), el);
    }
    return out;
}

static char* kr_replaceat(const char* lst, const char* idxs, const char* val) {
    int idx = atoi(idxs);
    int cnt = kr_listlen(lst);
    if (idx < 0 || idx >= cnt) return kr_str(lst);
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i++) {
        char* el = (i == idx) ? (char*)val : kr_split(lst, kr_itoa(i));
        if (first) { out = el; first = 0; }
        else out = kr_cat(kr_cat(out, ","), el);
    }
    return out;
}

static char* kr_fill(const char* ns, const char* val) {
    int n = atoi(ns);
    if (n <= 0) return _K_EMPTY;
    char* out = kr_str(val);
    for (int i = 1; i < n; i++) out = kr_cat(kr_cat(out, ","), val);
    return out;
}

static char* kr_zip(const char* a, const char* b) {
    int ac = kr_listlen(a), bc = kr_listlen(b);
    int mc = ac < bc ? ac : bc;
    if (!*a || !*b) return _K_EMPTY;
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < mc; i++) {
        char* ai = kr_split(a, kr_itoa(i));
        char* bi = kr_split(b, kr_itoa(i));
        if (first) { out = kr_cat(kr_cat(ai, ","), bi); first = 0; }
        else { out = kr_cat(kr_cat(out, ","), kr_cat(kr_cat(ai, ","), bi)); }
    }
    return out;
}

static char* kr_every(const char* lst, const char* val) {
    if (!*lst) return _K_ONE;
    int cnt = kr_listlen(lst);
    for (int i = 0; i < cnt; i++) {
        if (strcmp(kr_split(lst, kr_itoa(i)), val) != 0) return _K_ZERO;
    }
    return _K_ONE;
}

static char* kr_some(const char* lst, const char* val) {
    if (!*lst) return _K_ZERO;
    int cnt = kr_listlen(lst);
    for (int i = 0; i < cnt; i++) {
        if (strcmp(kr_split(lst, kr_itoa(i)), val) == 0) return _K_ONE;
    }
    return _K_ZERO;
}

static char* kr_countof(const char* lst, const char* item) {
    if (!*lst) return _K_ZERO;
    int cnt = kr_listlen(lst), c = 0;
    for (int i = 0; i < cnt; i++) {
        if (strcmp(kr_split(lst, kr_itoa(i)), item) == 0) c++;
    }
    return kr_itoa(c);
}

static char* kr_sumlist(const char* lst) {
    if (!*lst) return _K_ZERO;
    int cnt = kr_listlen(lst), s = 0;
    for (int i = 0; i < cnt; i++) s += atoi(kr_split(lst, kr_itoa(i)));
    return kr_itoa(s);
}

static char* kr_maxlist(const char* lst) {
    if (!*lst) return _K_ZERO;
    int cnt = kr_listlen(lst);
    int m = atoi(kr_split(lst, _K_ZERO));
    for (int i = 1; i < cnt; i++) {
        int v = atoi(kr_split(lst, kr_itoa(i)));
        if (v > m) m = v;
    }
    return kr_itoa(m);
}

static char* kr_minlist(const char* lst) {
    if (!*lst) return _K_ZERO;
    int cnt = kr_listlen(lst);
    int m = atoi(kr_split(lst, _K_ZERO));
    for (int i = 1; i < cnt; i++) {
        int v = atoi(kr_split(lst, kr_itoa(i)));
        if (v < m) m = v;
    }
    return kr_itoa(m);
}

static char* kr_hex(const char* s) {
    int v = atoi(s);
    char buf[32];
    snprintf(buf, sizeof(buf), "%x", v < 0 ? -v : v);
    if (v < 0) return kr_cat("-", kr_str(buf));
    return kr_str(buf);
}

static char* kr_bin(const char* s) {
    int v = atoi(s);
    if (v == 0) return _K_ZERO;
    int neg = v < 0; if (neg) v = -v;
    char buf[64]; int i = 63; buf[i] = 0;
    while (v > 0) { buf[--i] = '0' + (v & 1); v >>= 1; }
    if (neg) return kr_cat("-", kr_str(&buf[i]));
    return kr_str(&buf[i]);
}

typedef struct EnvEntry { char* name; char* value; struct EnvEntry* prev; } EnvEntry;

static char* kr_envnew() { return (char*)0; }

static char* kr_envset(char* envp, const char* name, const char* val) {
    EnvEntry* e = (EnvEntry*)_alloc(sizeof(EnvEntry));
    e->name = (char*)name;
    e->value = (char*)val;
    e->prev = (EnvEntry*)envp;
    return (char*)e;
}

static char* kr_envget(char* envp, const char* name) {
    EnvEntry* e = (EnvEntry*)envp;
    while (e) {
        if (strcmp(e->name, name) == 0) return e->value;
        e = e->prev;
    }
    if (strcmp(name, "__argOffset") != 0)
        fprintf(stderr, "ERROR: undefined variable: %s\n", name);
    return kr_str("");
}

typedef struct ResultStruct { char tag; char* val; char* env; int pos; } ResultStruct;

static char* kr_makeresult(const char* tag, const char* val, const char* env, const char* pos) {
    ResultStruct* r = (ResultStruct*)_alloc(sizeof(ResultStruct));
    r->tag = tag[0];
    r->val = (char*)val;
    r->env = (char*)env;
    r->pos = atoi(pos);
    return (char*)r;
}

static char* kr_getresulttag(const char* r) {
    char buf[2] = {((ResultStruct*)r)->tag, 0};
    return kr_str(buf);
}

static char* kr_getresultval(const char* r) {
    return ((ResultStruct*)r)->val;
}

static char* kr_getresultenv(const char* r) {
    return ((ResultStruct*)r)->env;
}

static char* kr_getresultpos(const char* r) {
    return kr_itoa(((ResultStruct*)r)->pos);
}

static char* kr_istruthy(const char* s) {
    if (!s || !*s || strcmp(s, "0") == 0 || strcmp(s, "false") == 0)
        return _K_ZERO;
    return _K_ONE;
}

typedef struct { int cap; int len; } SBHdr;
#define MAX_SBS 4096
static SBHdr* _sb_table[MAX_SBS];
static int _sb_count = 0;

static char* kr_sbnew() {
    int initcap = 65536;
    SBHdr* h = (SBHdr*)malloc(sizeof(SBHdr) + initcap);
    h->cap = initcap;
    h->len = 0;
    ((char*)(h + 1))[0] = 0;
    _sb_table[_sb_count] = h;
    return kr_itoa(_sb_count++);
}

static char* kr_sbappend(const char* handle, const char* s) {
    int idx = atoi(handle);
    SBHdr* h = _sb_table[idx];
    int slen = (int)strlen(s);
    while (h->len + slen + 1 > h->cap) {
        int newcap = h->cap * 2;
        h = (SBHdr*)realloc(h, sizeof(SBHdr) + newcap);
        h->cap = newcap;
    }
    memcpy((char*)(h + 1) + h->len, s, slen);
    h->len += slen;
    ((char*)(h + 1))[h->len] = 0;
    _sb_table[idx] = h;
    return kr_str(handle);
}

static char* kr_sbtostring(const char* handle) {
    int idx = atoi(handle);
    SBHdr* h = _sb_table[idx];
    return (char*)(h + 1);
}

#include <setjmp.h>
#define _KR_TRY_MAX 256
static jmp_buf _kr_try_stack[_KR_TRY_MAX];
static char*   _kr_err_stack[_KR_TRY_MAX];
static int     _kr_try_depth = 0;

static jmp_buf* _kr_pushtry() {
    _kr_err_stack[_kr_try_depth] = _K_EMPTY;
    return &_kr_try_stack[_kr_try_depth++];
}

static char* _kr_poptry() {
    if (_kr_try_depth > 0) _kr_try_depth--;
    return _kr_err_stack[_kr_try_depth];
}

static char* _kr_throw(const char* msg) {
    if (_kr_try_depth > 0) {
        _kr_err_stack[_kr_try_depth - 1] = (char*)msg;
        longjmp(_kr_try_stack[_kr_try_depth - 1], 1);
    }
    fprintf(stderr, "Uncaught exception: %s\n", msg);
    exit(1);
    return _K_EMPTY;
}

static char* kr_strreverse(const char* s) {
    int n = (int)strlen(s);
    char* out = _alloc(n + 1);
    for (int i = 0; i < n; i++) out[i] = s[n - 1 - i];
    out[n] = 0;
    return out;
}

static char* kr_words(const char* s) {
    if (!*s) return _K_EMPTY;
    char* out = _K_EMPTY; int first = 1;
    const char* p = s;
    while (*p == ' ' || *p == '\t') p++;
    const char* start = p;
    while (1) {
        if (*p == ' ' || *p == '\t' || *p == 0) {
            if (p > start) {
                int n = (int)(p - start);
                char* w = _alloc(n + 1);
                memcpy(w, start, n); w[n] = 0;
                if (first) { out = w; first = 0; }
                else out = kr_cat(kr_cat(out, ","), w);
            }
            if (!*p) break;
            while (*p == ' ' || *p == '\t') p++;
            start = p;
        } else { p++; }
    }
    return out;
}

static char* kr_lines(const char* s) {
    if (!*s) return _K_EMPTY;
    char* out = _K_EMPTY; int first = 1;
    const char* p = s, *start = s;
    while (1) {
        if (*p == '\n' || *p == 0) {
            int n = (int)(p - start);
            if (n > 0 && start[n-1] == '\r') n--;
            char* ln = _alloc(n + 1);
            memcpy(ln, start, n); ln[n] = 0;
            if (first) { out = ln; first = 0; }
            else out = kr_cat(kr_cat(out, ","), ln);
            if (!*p) break;
            start = p + 1;
        }
        p++;
    }
    return out;
}

static char* kr_first(const char* lst) { return kr_split(lst, _K_ZERO); }

static char* kr_last(const char* lst) {
    int cnt = kr_listlen(lst);
    if (cnt == 0) return _K_EMPTY;
    return kr_split(lst, kr_itoa(cnt - 1));
}

static char* kr_head(const char* lst, const char* ns) {
    int n = atoi(ns), cnt = kr_listlen(lst);
    if (n <= 0 || !*lst) return _K_EMPTY;
    if (n >= cnt) return kr_str(lst);
    char* out = kr_split(lst, _K_ZERO);
    for (int i = 1; i < n; i++) out = kr_cat(kr_cat(out, ","), kr_split(lst, kr_itoa(i)));
    return out;
}

static char* kr_tail(const char* lst, const char* ns) {
    int n = atoi(ns), cnt = kr_listlen(lst);
    if (n <= 0 || !*lst) return _K_EMPTY;
    if (n >= cnt) return kr_str(lst);
    int start = cnt - n;
    char* out = kr_split(lst, kr_itoa(start));
    for (int i = start + 1; i < cnt; i++) out = kr_cat(kr_cat(out, ","), kr_split(lst, kr_itoa(i)));
    return out;
}

static char* kr_lstrip(const char* s) {
    while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r') s++;
    return kr_str(s);
}

static char* kr_rstrip(const char* s) {
    int len = (int)strlen(s);
    while (len > 0 && (s[len-1]==' '||s[len-1]=='\t'||s[len-1]=='\n'||s[len-1]=='\r')) len--;
    char* r = _alloc(len + 1);
    memcpy(r, s, len); r[len] = 0;
    return r;
}

static char* kr_center(const char* s, const char* ws, const char* pad) {
    int w = atoi(ws), slen = (int)strlen(s), plen = (int)strlen(pad);
    if (slen >= w || plen == 0) return kr_str(s);
    int total = w - slen;
    int left = total / 2, right = total - left;
    char* out = _alloc(w + 1);
    for (int i = 0; i < left; i++) out[i] = pad[i % plen];
    memcpy(out + left, s, slen);
    for (int i = 0; i < right; i++) out[left + slen + i] = pad[i % plen];
    out[w] = 0;
    return out;
}

static char* kr_isalpha(const char* s) {
    if (!*s) return _K_ZERO;
    for (const char* p = s; *p; p++) if (!isalpha((unsigned char)*p)) return _K_ZERO;
    return _K_ONE;
}

static char* kr_isdigit(const char* s) {
    if (!*s) return _K_ZERO;
    for (const char* p = s; *p; p++) if (!isdigit((unsigned char)*p)) return _K_ZERO;
    return _K_ONE;
}

static char* kr_isspace(const char* s) {
    if (!*s) return _K_ZERO;
    for (const char* p = s; *p; p++) if (!isspace((unsigned char)*p)) return _K_ZERO;
    return _K_ONE;
}

static char* kr_random(const char* ns) {
    int n = atoi(ns);
    if (n <= 0) return _K_ZERO;
    return kr_itoa(rand() % n);
}

static char* kr_timestamp() {
    return kr_itoa((int)time(NULL));
}

static char* kr_environ(const char* name) {
    const char* v = getenv(name);
    if (!v) return _K_EMPTY;
    return kr_str(v);
}

static char* kr_floor(const char* s) { return kr_itoa((int)atoi(s)); }
static char* kr_ceil(const char* s)  { return kr_itoa((int)atoi(s)); }
static char* kr_round(const char* s) { return kr_itoa((int)atoi(s)); }

static char* kr_throw(const char* msg) { return _kr_throw(msg); }

static char* kr_structnew() {
    // 2 slots for count + up to 32 fields (name+val pairs)
    char** s = (char**)_alloc(66 * sizeof(char*));
    s[0] = _K_ZERO; // field count
    return (char*)s;
}

static char* kr_setfield(char* obj, const char* name, const char* val) {
    char** s = (char**)obj;
    int cnt = atoi(s[0]);
    // search for existing field
    for (int i = 0; i < cnt; i++) {
        if (strcmp(s[1 + i*2], name) == 0) {
            s[2 + i*2] = (char*)val;
            return obj;
        }
    }
    // add new field
    s[1 + cnt*2] = (char*)name;
    s[2 + cnt*2] = (char*)val;
    s[0] = kr_itoa(cnt + 1);
    return obj;
}

static char* kr_getfield(char* obj, const char* name) {
    if (!obj) return _K_EMPTY;
    char** s = (char**)obj;
    int cnt = atoi(s[0]);
    for (int i = 0; i < cnt; i++) {
        if (strcmp(s[1 + i*2], name) == 0) return s[2 + i*2];
    }
    return _K_EMPTY;
}

static char* kr_hasfield(char* obj, const char* name) {
    if (!obj) return _K_ZERO;
    char** s = (char**)obj;
    int cnt = atoi(s[0]);
    for (int i = 0; i < cnt; i++) {
        if (strcmp(s[1 + i*2], name) == 0) return _K_ONE;
    }
    return _K_ZERO;
}

static char* kr_structfields(char* obj) {
    if (!obj) return _K_EMPTY;
    char** s = (char**)obj;
    int cnt = atoi(s[0]);
    if (cnt == 0) return _K_EMPTY;
    char* out = s[1];
    for (int i = 1; i < cnt; i++) out = kr_cat(kr_cat(out, ","), s[1 + i*2]);
    return out;
}

static char* kr_mapget(const char* map, const char* key) {
    if (!*map) return _K_EMPTY;
    int cnt = kr_listlen(map);
    for (int i = 0; i < cnt - 1; i += 2) {
        if (strcmp(kr_split(map, kr_itoa(i)), key) == 0)
            return kr_split(map, kr_itoa(i + 1));
    }
    return _K_EMPTY;
}

static char* kr_mapset(const char* map, const char* key, const char* val) {
    if (!*map) return kr_cat(kr_cat(kr_str(key), ","), val);
    int cnt = kr_listlen(map);
    char* out = _K_EMPTY; int first = 1; int found = 0;
    for (int i = 0; i < cnt - 1; i += 2) {
        char* k = kr_split(map, kr_itoa(i));
        char* v = (strcmp(k, key) == 0) ? (char*)val : kr_split(map, kr_itoa(i+1));
        if (strcmp(k, key) == 0) found = 1;
        if (first) { out = kr_cat(k, kr_cat(",", v)); first = 0; }
        else out = kr_cat(out, kr_cat(",", kr_cat(k, kr_cat(",", v))));
    }
    if (!found) {
        if (first) out = kr_cat(kr_str(key), kr_cat(",", val));
        else out = kr_cat(out, kr_cat(",", kr_cat(kr_str(key), kr_cat(",", val))));
    }
    return out;
}

static char* kr_mapdel(const char* map, const char* key) {
    if (!*map) return _K_EMPTY;
    int cnt = kr_listlen(map);
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt - 1; i += 2) {
        char* k = kr_split(map, kr_itoa(i));
        if (strcmp(k, key) != 0) {
            char* v = kr_split(map, kr_itoa(i+1));
            if (first) { out = kr_cat(k, kr_cat(",", v)); first = 0; }
            else out = kr_cat(out, kr_cat(",", kr_cat(k, kr_cat(",", v))));
        }
    }
    return out;
}

static char* kr_sprintf(const char* fmt, ...) {
    char buf[4096];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    return kr_str(buf);
}

static char* kr_strsplit(const char* s, const char* delim) {
    return kr_splitby(s, delim);
}

static char* kr_listmap(const char* lst, const char* prefix, const char* suffix) {
    if (!*lst) return _K_EMPTY;
    int cnt = kr_listlen(lst);
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i++) {
        char* item = kr_split(lst, kr_itoa(i));
        char* mapped = kr_cat(kr_cat(kr_str(prefix), item), suffix);
        if (first) { out = mapped; first = 0; }
        else out = kr_cat(out, kr_cat(",", mapped));
    }
    return out;
}

static char* kr_listfilter(const char* lst, const char* val) {
    if (!*lst) return _K_EMPTY;
    int cnt = kr_listlen(lst), negate = 0;
    const char* match = val;
    if (val[0] == '!') { negate = 1; match = val + 1; }
    char* out = _K_EMPTY; int first = 1;
    for (int i = 0; i < cnt; i++) {
        char* item = kr_split(lst, kr_itoa(i));
        int eq = (strcmp(item, match) == 0);
        int keep = negate ? !eq : eq;
        if (keep) {
            if (first) { out = item; first = 0; }
            else out = kr_cat(out, kr_cat(",", item));
        }
    }
    return out;
}

#include <math.h>
static char* kr_tofloat(const char* s) {
    return s;
}

static char* kr_fadd(const char* a,const char* b){char buf[64];snprintf(buf,64,"%g",atof(a)+atof(b));return kr_str(buf);}
static char* kr_fsub(const char* a,const char* b){char buf[64];snprintf(buf,64,"%g",atof(a)-atof(b));return kr_str(buf);}
static char* kr_fmul(const char* a,const char* b){char buf[64];snprintf(buf,64,"%g",atof(a)*atof(b));return kr_str(buf);}
static char* kr_fdiv(const char* a,const char* b){char buf[64];if(atof(b)==0.0)return kr_str("0");snprintf(buf,64,"%g",atof(a)/atof(b));return kr_str(buf);}
static char* kr_flt(const char* a,const char* b){return atof(a)<atof(b)?_K_ONE:_K_ZERO;}
static char* kr_fgt(const char* a,const char* b){return atof(a)>atof(b)?_K_ONE:_K_ZERO;}
static char* kr_feq(const char* a,const char* b){return atof(a)==atof(b)?_K_ONE:_K_ZERO;}
static char* kr_fsqrt(const char* a) {
    char buf[64]; snprintf(buf,64,"%g",sqrt(atof(a)));
    return kr_str(buf);
}

static char* kr_ffloor(const char* a) {
    char buf[64]; snprintf(buf,64,"%.0f",floor(atof(a)));
    return kr_str(buf);
}

static char* kr_fceil(const char* a) {
    char buf[64]; snprintf(buf,64,"%.0f",ceil(atof(a)));
    return kr_str(buf);
}

static char* kr_fround(const char* a) {
    char buf[64]; snprintf(buf,64,"%.0f",round(atof(a)));
    return kr_str(buf);
}

static char* kr_fformat(const char* a,const char* prec){char fmt[32],buf[64];snprintf(fmt,32,"%%.%sf",prec);snprintf(buf,64,fmt,atof(a));return kr_str(buf);}
static char* kr_mkclosure(const char* fn,const char* env){int fl=strlen(fn),el=strlen(env);char* p=_alloc(fl+el+2);memcpy(p,fn,fl);p[fl]='|';memcpy(p+fl+1,env,el+1);return p;}
static char* kr_closure_fn(const char* c){const char* p=strchr(c,'|');if(!p)return(char*)c;int n=p-c;char* r2=_alloc(n+1);memcpy(r2,c,n);r2[n]=0;return r2;}
static char* kr_closure_env(const char* c){const char* p=strchr(c,'|');return p?(char*)(p+1):(char*)_K_EMPTY;}
#include "./kfetch_api.h"
// --- imported: utils.k ---
char* ansi(char*);
char* vislen(char*);
char* padansi(char*, char*);
char* firstpart(char*, char*);
char* afterpart(char*, char*);
char* linecount(char*);
char* nthline(char*, char*);
char* idxfrom(char*, char*, char*);
// --- imported: cpu.k ---
char* cpubrand();
char* cpucores();
char* sysarch();
char* sysuser();
char* syshost();
// --- imported: os.k ---
char* osver();
char* uptime();
// --- imported: mem.k ---
char* raminfo();
// --- imported: disk.k ---
char* driveinfo();
// --- imported: gpu.k ---
char* gpunames();

char* ansi(char* s) {
    char* esc = kr_fromcharcode(kr_str("27"));
    return kr_replace(s, kr_str("\\x1b"), esc);
}

char* vislen(char* s) {
    char* total = kr_len(s);
    char* vis = kr_str("0");
    char* i = kr_str("0");
    char* esc = kr_fromcharcode(kr_str("27"));
    while (kr_truthy(kr_lt(kr_toint(i), kr_toint(total)))) {
        char* ch = kr_substr(s, kr_toint(i), kr_plus(kr_toint(i), kr_str("1")));
        if (kr_truthy(kr_eq(ch, esc))) {
            i = kr_plus(kr_plus(kr_toint(i), kr_str("1")), kr_str(""));
            while (kr_truthy(kr_lt(kr_toint(i), kr_toint(total)))) {
                char* c2 = kr_substr(s, kr_toint(i), kr_plus(kr_toint(i), kr_str("1")));
                i = kr_plus(kr_plus(kr_toint(i), kr_str("1")), kr_str(""));
                if (kr_truthy(kr_eq(c2, kr_str("m")))) {
                    break;
                }
            }
        } else {
            vis = kr_plus(kr_plus(kr_toint(vis), kr_str("1")), kr_str(""));
            i = kr_plus(kr_plus(kr_toint(i), kr_str("1")), kr_str(""));
        }
    }
    return vis;
}

char* padansi(char* s, char* w) {
    char* vl = kr_toint(((char*(*)(char*))vislen)(s));
    char* pad = kr_sub(kr_toint(w), vl);
    char* result = s;
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(kr_toint(i), pad))) {
        result = kr_plus(result, kr_str(" "));
        i = kr_plus(kr_plus(kr_toint(i), kr_str("1")), kr_str(""));
    }
    return result;
}

char* firstpart(char* s, char* delim) {
    char* pos = kr_indexof(s, delim);
    if (kr_truthy(kr_lt(pos, kr_str("0")))) {
        return s;
    }
    return kr_substr(s, kr_str("0"), kr_toint(pos));
}

char* afterpart(char* s, char* delim) {
    char* pos = kr_indexof(s, delim);
    if (kr_truthy(kr_lt(pos, kr_str("0")))) {
        return kr_str("");
    }
    return kr_substr(s, kr_plus(kr_toint(pos), kr_str("1")), kr_len(s));
}

char* linecount(char* s) {
    if (kr_truthy(kr_eq(s, kr_str("")))) {
        return kr_str("0");
    }
    char* t = kr_trim(s);
    if (kr_truthy(kr_eq(t, kr_str("")))) {
        return kr_str("0");
    }
    char* n = kr_str("1");
    char* i = kr_str("0");
    while (kr_truthy(kr_lt(kr_toint(i), kr_len(t)))) {
        char* ch = kr_substr(t, kr_toint(i), kr_plus(kr_toint(i), kr_str("1")));
        if (kr_truthy(kr_eq(ch, kr_str("\n")))) {
            n = kr_plus(kr_plus(kr_toint(n), kr_str("1")), kr_str(""));
        }
        i = kr_plus(kr_plus(kr_toint(i), kr_str("1")), kr_str(""));
    }
    return n;
}

char* nthline(char* s, char* lineIdx) {
    char* target = kr_toint(lineIdx);
    char* cur = kr_str("0");
    char* start = kr_str("0");
    char* done = kr_str("0");
    while (kr_truthy(kr_eq(done, kr_str("0")))) {
        char* rest = kr_substr(s, kr_toint(start), kr_len(s));
        char* nlPos = kr_indexof(rest, kr_str("\n"));
        if (kr_truthy(kr_lt(nlPos, kr_str("0")))) {
            if (kr_truthy(kr_eq(kr_toint(cur), target))) {
                return kr_trim(rest);
            }
            done = kr_str("1");
        } else {
            if (kr_truthy(kr_eq(kr_toint(cur), target))) {
                return kr_trim(kr_substr(rest, kr_str("0"), kr_toint(nlPos)));
            }
            start = kr_plus(kr_plus(kr_plus(kr_toint(start), kr_toint(nlPos)), kr_str("1")), kr_str(""));
            cur = kr_plus(kr_plus(kr_toint(cur), kr_str("1")), kr_str(""));
        }
    }
    return kr_str("");
}

char* idxfrom(char* s, char* sub, char* start) {
    char* slen = kr_len(s);
    char* sublen = kr_len(sub);
    char* i = kr_toint(start);
    while (kr_truthy(kr_lte(kr_toint(i), kr_sub(kr_toint(slen), kr_toint(sublen))))) {
        char* piece = kr_substr(s, kr_toint(i), kr_plus(kr_toint(i), kr_toint(sublen)));
        if (kr_truthy(kr_eq(piece, sub))) {
            return kr_plus(i, kr_str(""));
        }
        i = kr_plus(kr_plus(kr_toint(i), kr_str("1")), kr_str(""));
    }
    return kr_str("-1");
}

char* cpubrand() {
    char* raw = ((char*(*)(char*))exec)(kr_str("powershell -NoProfile -Command \"(Get-WmiObject Win32_Processor).Name\""));
    char* r = kr_trim(raw);
    if (kr_truthy(kr_eq(r, kr_str("")))) {
        return kr_str("Unknown CPU");
    }
    return r;
}

char* cpucores() {
    char* cr = ((char*(*)(char*))exec)(kr_str("powershell -NoProfile -Command \"(Get-WmiObject Win32_Processor).NumberOfCores\""));
    char* tr = ((char*(*)(char*))exec)(kr_str("powershell -NoProfile -Command \"(Get-WmiObject Win32_Processor).NumberOfLogicalProcessors\""));
    char* cores = kr_trim(cr);
    char* threads = kr_trim(tr);
    if (kr_truthy(kr_eq(cores, kr_str("")))) {
        cores = kr_str("?");
    }
    if (kr_truthy(kr_eq(threads, kr_str("")))) {
        threads = kr_str("?");
    }
    return kr_plus(kr_plus(cores, kr_str(",")), threads);
}

char* sysarch() {
    return kr_trim(((char*(*)(char*))exec)(kr_str("echo %PROCESSOR_ARCHITECTURE%")));
}

char* sysuser() {
    return kr_trim(((char*(*)(char*))exec)(kr_str("echo %USERNAME%")));
}

char* syshost() {
    return kr_trim(((char*(*)(char*))exec)(kr_str("echo %COMPUTERNAME%")));
}

char* osver() {
    char* raw = ((char*(*)(char*))exec)(kr_str("powershell -NoProfile -Command \"(Get-WmiObject Win32_OperatingSystem).BuildNumber\""));
    char* build = kr_trim(raw);
    if (kr_truthy(kr_eq(build, kr_str("")))) {
        build = kr_str("0");
    }
    char* b = kr_toint(build);
    char* v = kr_str("Windows");
    if (kr_truthy(kr_gte(b, kr_str("26100")))) {
        v = kr_str("Windows 11");
    } else if (kr_truthy(kr_gte(b, kr_str("22621")))) {
        v = kr_str("Windows 11");
    } else if (kr_truthy(kr_gte(b, kr_str("22000")))) {
        v = kr_str("Windows 11");
    } else if (kr_truthy(kr_gte(b, kr_str("19041")))) {
        v = kr_str("Windows 10");
    } else {
        v = kr_str("Windows (legacy)");
    }
    return kr_plus(kr_plus(kr_plus(v, kr_str(" (build ")), build), kr_str(")"));
}

char* uptime() {
    char* ms = ((char*(*)(void))kfticks)();
    char* tsec = kr_div(kr_toint(ms), kr_str("1000"));
    char* mins = kr_div(tsec, kr_str("60"));
    char* hrs = kr_div(mins, kr_str("60"));
    char* days = kr_div(hrs, kr_str("24"));
    char* h = kr_sub(hrs, kr_mul(days, kr_str("24")));
    char* m = kr_sub(mins, kr_mul(hrs, kr_str("60")));
    if (kr_truthy(kr_gt(days, kr_str("0")))) {
        return kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(days, kr_str(" days, ")), h), kr_str(" hrs, ")), m), kr_str(" min"));
    } else if (kr_truthy(kr_gt(hrs, kr_str("0")))) {
        return kr_plus(kr_plus(kr_plus(h, kr_str(" hrs, ")), m), kr_str(" min"));
    } else {
        return kr_plus(m, kr_str(" min"));
    }
}

char* raminfo() {
    return ((char*(*)(void))kfmem)();
}

char* driveinfo() {
    return ((char*(*)(void))kfdisk)();
}

char* gpunames() {
    char* raw = ((char*(*)(char*))exec)(kr_str("powershell -NoProfile -Command \"(Get-WmiObject Win32_VideoController).Name\""));
    char* result = kr_trim(raw);
    if (kr_truthy(kr_eq(result, kr_str("")))) {
        return kr_str("Unknown GPU");
    }
    return result;
}

char* run();

char* run() {
    ((char*(*)(void))kfinit)();
    ((char*(*)(void))kfcls)();
    char* E = kr_fromcharcode(kr_str("27"));
    char* GRN = kr_plus(E, kr_str("[32;1m"));
    char* CYN = kr_plus(E, kr_str("[36;1m"));
    char* RST = kr_plus(E, kr_str("[0m"));
    char* LW = kr_str("40");
    char* l0 = ((char*(*)(char*))ansi)(kr_str("\\x1b[34m        ,.=:!!t3Z3z.,\\x1b[0m"));
    char* l1 = ((char*(*)(char*))ansi)(kr_str("\\x1b[34m       :tt:::tt333EE3\\x1b[0m"));
    char* l2 = ((char*(*)(char*))ansi)(kr_str("\\x1b[34m       Et:::ztt33EEEL\\x1b[36m @Ee.,      ..,\\x1b[0m"));
    char* l3 = ((char*(*)(char*))ansi)(kr_str("\\x1b[34m      ;tt:::tt333EE7\\x1b[36m ;EEEEEEttttt33#\\x1b[0m"));
    char* l4 = ((char*(*)(char*))ansi)(kr_str("\\x1b[34m     :Et:::zt333EEQ\\x1b[36m  SEEEEEttttt33QL\\x1b[0m"));
    char* l5 = ((char*(*)(char*))ansi)(kr_str("\\x1b[34m     it::::tt333EEF\\x1b[36m @EEEEttttt33F\\x1b[0m"));
    char* l6 = ((char*(*)(char*))ansi)(kr_str("\\x1b[34m    ;3=*^   \"*4EEV\\x1b[36m :EEEEttttt33@.\\x1b[0m"));
    char* l7 = ((char*(*)(char*))ansi)(kr_str("\\x1b[36m    ,.=::::!t=.,\\x1b[34m  @EEEEtttz33QF\\x1b[0m"));
    char* l8 = ((char*(*)(char*))ansi)(kr_str("\\x1b[36m   ;::::::::zt33)\\x1b[34m   \"4EEEtttji\\x1b[0m"));
    char* l9 = ((char*(*)(char*))ansi)(kr_str("\\x1b[36m  :t::::::::tt33.\\x1b[34m :Z3z..    \\x1b[0m"));
    char* l10 = ((char*(*)(char*))ansi)(kr_str("\\x1b[36m  i::::::::zt33F\\x1b[34m AEEEtttt::::ztF\\x1b[0m"));
    char* l11 = ((char*(*)(char*))ansi)(kr_str("\\x1b[36m ;:::::::::t33V\\x1b[34m ;EEEttttt::::t3\\x1b[0m"));
    char* l12 = ((char*(*)(char*))ansi)(kr_str("\\x1b[36m E::::::::zt33L\\x1b[34m @EEEtttt::::z3F\\x1b[0m"));
    char* l13 = ((char*(*)(char*))ansi)(kr_str("\\x1b[36m{3=*^   \"*4E3)\\x1b[34m ;EEEtttt:::::tZ\\x1b[0m"));
    char* l14 = ((char*(*)(char*))ansi)(kr_str("\\x1b[36m            \\x1b[34m :EEEEtttt::::z7\\x1b[0m"));
    char* l15 = ((char*(*)(char*))ansi)(kr_str("\\x1b[34m                 \"VEzjt:;;z>*\\x1b[0m"));
    char* usr = ((char*(*)(void))sysuser)();
    char* host = ((char*(*)(void))syshost)();
    char* arch = ((char*(*)(void))sysarch)();
    char* os = ((char*(*)(void))osver)();
    char* cpu = ((char*(*)(void))cpubrand)();
    char* ci = ((char*(*)(void))cpucores)();
    char* cn = ((char*(*)(char*,char*))firstpart)(ci, kr_str(","));
    char* tn = ((char*(*)(char*,char*))afterpart)(ci, kr_str(","));
    char* mi = ((char*(*)(void))raminfo)();
    char* tmb = ((char*(*)(char*,char*))firstpart)(mi, kr_str(","));
    char* fmb = ((char*(*)(char*,char*))afterpart)(mi, kr_str(","));
    char* umb = kr_plus(kr_sub(kr_toint(tmb), kr_toint(fmb)), kr_str(""));
    char* tgb = kr_plus(kr_div(kr_toint(tmb), kr_str("1024")), kr_str(""));
    char* ugb = kr_plus(kr_div(kr_toint(umb), kr_str("1024")), kr_str(""));
    char* di = ((char*(*)(void))driveinfo)();
    char* d1 = ((char*(*)(char*,char*))nthline)(di, kr_str("0"));
    char* d2 = ((char*(*)(char*,char*))nthline)(di, kr_str("1"));
    char* d3 = ((char*(*)(char*,char*))nthline)(di, kr_str("2"));
    char* gp = ((char*(*)(void))gpunames)();
    char* ng = ((char*(*)(char*))linecount)(gp);
    char* g1 = kr_str("");
    char* g2 = kr_str("");
    if (kr_truthy(kr_eq(ng, kr_str("1")))) {
        g1 = gp;
    }
    if (kr_truthy(kr_gte(kr_toint(ng), kr_str("2")))) {
        g1 = ((char*(*)(char*,char*))nthline)(gp, kr_str("0"));
        g2 = ((char*(*)(char*,char*))nthline)(gp, kr_str("1"));
    }
    if (kr_truthy(kr_eq(g1, kr_str("")))) {
        g1 = kr_str("None");
    }
    char* tc = ((char*(*)(void))kfconsize)();
    char* cols = ((char*(*)(char*,char*))firstpart)(tc, kr_str(","));
    char* rows = ((char*(*)(char*,char*))afterpart)(tc, kr_str(","));
    char* up = ((char*(*)(void))uptime)();
    char* lb0 = kr_str("User");
    char* v0 = kr_plus(kr_plus(usr, kr_str("@")), host);
    char* lb1 = kr_str("OS");
    char* v1 = kr_plus(kr_plus(os, kr_str(" ")), arch);
    char* lb2 = kr_str("CPU");
    char* v2 = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(cpu, kr_str(" (")), cn), kr_str("c / ")), tn), kr_str("t)"));
    char* lb3 = kr_str("RAM");
    char* v3 = kr_plus(kr_plus(kr_plus(ugb, kr_str(" GB / ")), tgb), kr_str(" GB"));
    char* lb4 = kr_str("Disk");
    char* v4 = d1;
    char* lb5 = kr_str("");
    char* v5 = d2;
    char* lb6 = kr_str("");
    char* v6 = d3;
    char* lb7 = kr_str("GPU");
    char* v7 = g1;
    char* lb8 = kr_str("GPU2");
    char* v8 = g2;
    char* lb9 = kr_str("Term");
    char* v9 = kr_plus(kr_plus(cols, kr_str("x")), rows);
    char* lb10 = kr_str("Uptime");
    char* v10 = up;
    char* idx = kr_str("0");
    while (kr_truthy(kr_lt(kr_toint(idx), kr_str("16")))) {
        char* logo = kr_str("");
        if (kr_truthy(kr_eq(idx, kr_str("0")))) {
            logo = l0;
        }
        if (kr_truthy(kr_eq(idx, kr_str("1")))) {
            logo = l1;
        }
        if (kr_truthy(kr_eq(idx, kr_str("2")))) {
            logo = l2;
        }
        if (kr_truthy(kr_eq(idx, kr_str("3")))) {
            logo = l3;
        }
        if (kr_truthy(kr_eq(idx, kr_str("4")))) {
            logo = l4;
        }
        if (kr_truthy(kr_eq(idx, kr_str("5")))) {
            logo = l5;
        }
        if (kr_truthy(kr_eq(idx, kr_str("6")))) {
            logo = l6;
        }
        if (kr_truthy(kr_eq(idx, kr_str("7")))) {
            logo = l7;
        }
        if (kr_truthy(kr_eq(idx, kr_str("8")))) {
            logo = l8;
        }
        if (kr_truthy(kr_eq(idx, kr_str("9")))) {
            logo = l9;
        }
        if (kr_truthy(kr_eq(idx, kr_str("10")))) {
            logo = l10;
        }
        if (kr_truthy(kr_eq(idx, kr_str("11")))) {
            logo = l11;
        }
        if (kr_truthy(kr_eq(idx, kr_str("12")))) {
            logo = l12;
        }
        if (kr_truthy(kr_eq(idx, kr_str("13")))) {
            logo = l13;
        }
        if (kr_truthy(kr_eq(idx, kr_str("14")))) {
            logo = l14;
        }
        if (kr_truthy(kr_eq(idx, kr_str("15")))) {
            logo = l15;
        }
        char* lb = kr_str("");
        char* v = kr_str("");
        if (kr_truthy(kr_eq(idx, kr_str("0")))) {
            lb = lb0;
            v = v0;
        }
        if (kr_truthy(kr_eq(idx, kr_str("1")))) {
            lb = lb1;
            v = v1;
        }
        if (kr_truthy(kr_eq(idx, kr_str("2")))) {
            lb = lb2;
            v = v2;
        }
        if (kr_truthy(kr_eq(idx, kr_str("3")))) {
            lb = lb3;
            v = v3;
        }
        if (kr_truthy(kr_eq(idx, kr_str("4")))) {
            lb = lb4;
            v = v4;
        }
        if (kr_truthy(kr_eq(idx, kr_str("5")))) {
            lb = lb5;
            v = v5;
        }
        if (kr_truthy(kr_eq(idx, kr_str("6")))) {
            lb = lb6;
            v = v6;
        }
        if (kr_truthy(kr_eq(idx, kr_str("7")))) {
            lb = lb7;
            v = v7;
        }
        if (kr_truthy(kr_eq(idx, kr_str("8")))) {
            lb = lb8;
            v = v8;
        }
        if (kr_truthy(kr_eq(idx, kr_str("9")))) {
            lb = lb9;
            v = v9;
        }
        if (kr_truthy(kr_eq(idx, kr_str("10")))) {
            lb = lb10;
            v = v10;
        }
        char* info = kr_str("");
        if (kr_truthy(kr_neq(lb, kr_str("")))) {
            info = kr_plus(kr_plus(kr_plus(kr_plus(kr_plus(GRN, lb), kr_str(":")), RST), kr_str(" ")), v);
        } else {
            if (kr_truthy(kr_neq(v, kr_str("")))) {
                info = kr_plus(kr_str("       "), v);
            }
        }
        kr_print(kr_plus(kr_plus(((char*(*)(char*,char*))padansi)(logo, kr_toint(LW)), kr_str("  ")), info));
        idx = kr_plus(kr_plus(kr_toint(idx), kr_str("1")), kr_str(""));
    }
    kr_print(kr_str(""));
    kr_print(kr_plus(kr_plus(kr_plus(CYN, kr_str("  KryptonFetch")), RST), kr_str(" by KryptonBytes")));
    kr_print(kr_str(""));
    return kr_str("");
    kr_str("");
    run;
    kr_str("");
    ((char*(*)(void))run)();
}

int main(int argc, char** argv) {
    _argc = argc; _argv = argv;
    srand((unsigned)time(NULL));
    ((char*(*)(void))run)();
    return 0;
}

