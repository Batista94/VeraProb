self.onmessage = async function(event) {
  try {
    const buffer = event.data;
    if (!buffer) {
      throw new Error("Buffer not provided");
    }
    
    // Web Crypto API returns a Promise that resolves with an ArrayBuffer containing the hash
    const digestBuffer = await crypto.subtle.digest('SHA-256', buffer);
    
    // Convert ArrayBuffer to Hex String
    const hashArray = Array.from(new Uint8Array(digestBuffer));
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
    
    // Send result back to the main thread
    self.postMessage({ success: true, hash: hashHex });
  } catch (err) {
    self.postMessage({ success: false, error: err.message });
  }
};
