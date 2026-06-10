class_name ArtgenMultipart
extends RefCounted

## Hand-rolled multipart/form-data builder for HTTPRequest.request_raw —
## Recraft's style creation and removeBackground endpoints take file uploads.


## fields: {name: value}; files: array of
## {"name": String, "filename": String, "content_type": String, "bytes": PackedByteArray}.
## Returns {"body": PackedByteArray, "content_type": String}.
static func build(fields: Dictionary, files: Array) -> Dictionary:
	var boundary := "artgen" + Crypto.new().generate_random_bytes(12).hex_encode()
	var body := PackedByteArray()
	for key in fields:
		body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
		body.append_array((
			"Content-Disposition: form-data; name=\"%s\"\r\n\r\n" % key).to_utf8_buffer())
		body.append_array((str(fields[key]) + "\r\n").to_utf8_buffer())
	for f in files:
		body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
		body.append_array((
			"Content-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\n"
			% [f["name"], f["filename"]]).to_utf8_buffer())
		body.append_array((
			"Content-Type: %s\r\n\r\n"
			% f.get("content_type", "application/octet-stream")).to_utf8_buffer())
		body.append_array(f["bytes"])
		body.append_array("\r\n".to_utf8_buffer())
	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())
	return {"body": body, "content_type": "multipart/form-data; boundary=" + boundary}
