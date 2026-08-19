// Headless Node has no DOM. pdfjs-dist (pulled in by dsh-ai4scholar) reads
// DOMMatrix at import time and otherwise kills the whole plugin tree.
const shim = class {};
if (typeof globalThis.DOMMatrix === "undefined") globalThis.DOMMatrix = shim;
if (typeof globalThis.ImageData === "undefined") globalThis.ImageData = shim;
if (typeof globalThis.Path2D === "undefined") globalThis.Path2D = shim;
