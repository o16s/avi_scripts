project = 'Anisca Vision OpenWRT Camera'
copyright = '2024, Octanis'
author = 'Octanis'
release = '1.0'

extensions = []
templates_path = ['_templates']
exclude_patterns = []

html_theme = 'sphinx_rtd_theme'
html_static_path = ['_static']

# PDF output - SIMPLIFIED FOR COMPATIBILITY
latex_engine = 'pdflatex'
latex_elements = {
    'papersize': 'a4paper',
    'pointsize': '11pt',
    'preamble': r'''
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\DeclareUnicodeCharacter{2699}{\textbf{[GEAR]}}
\DeclareUnicodeCharacter{1F5C4}{\textbf{[FOLDER]}}
\DeclareUnicodeCharacter{1F512}{\textbf{[LOCK]}}
''',
}

latex_documents = [
    ('index', 'anisca-vision-openwrt-camera.tex', 'Anisca Vision OpenWRT Camera User Manual',
     'Octanis', 'manual'),
]