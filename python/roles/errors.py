"""Safe responses for unexpected API failures."""

from flask import current_app, jsonify, request


def internal_error(message="Internal server error.", **fields):
    """Log the active exception and return a public JSON response."""
    current_app.logger.exception("API request failed: %s %s", request.method, request.path)
    return jsonify({"success": False, "message": message, "error": message, **fields}), 500
