"""Canonical route names used by route-demand analysis.

This is intentionally limited to confirmed spelling variants. It does not
change the stored database values; it only prevents known aliases from being
counted as separate destinations during model analysis.
"""
import re
import unicodedata


def _comparison_key(value):
    text = unicodedata.normalize('NFKD', str(value or ''))
    text = ''.join(char for char in text if not unicodedata.combining(char))
    return re.sub(r'\s+', ' ', text.strip().lower())


_ALIASES = {
    'los banos': 'Los Baños',
    'tanauan': 'Tanauan',
    'tanuan': 'Tanauan',
}


def canonical_route_name(value):
    clean = re.sub(r'\s+', ' ', str(value or '').strip())
    if not clean:
        return 'Unknown'
    return _ALIASES.get(_comparison_key(clean), clean)
