project = 'Anisca Vision OpenWRT Camera'
copyright = '2024, Octanis'
author = 'Octanis'
release = '1.0'

extensions = []
templates_path = ['_templates']
exclude_patterns = []

html_theme = 'sphinx_rtd_theme'
html_static_path = ['_static']

# PDF output
latex_engine = 'xelatex'  # Changed from pdflatex to xelatex for better Unicode support
latex_elements = {
    'papersize': 'a4paper',
    'pointsize': '11pt',
    'preamble': r'''
\usepackage{fontspec}
\usepackage{xunicode}
\usepackage{xltxtra}
\defaultfontfeatures{Ligatures=TeX}
\setmainfont{DejaVu Sans}
\setsansfont{DejaVu Sans}
\setmonofont{DejaVu Sans Mono}
''',
    'babel': '',
    'inputenc': '',
    'utf8extra': '',
}

latex_documents = [
    ('index', 'anisca-vision-openwrt-camera.tex', 'Anisca Vision OpenWRT Camera User Manual',
     'Octanis', 'manual'),
]