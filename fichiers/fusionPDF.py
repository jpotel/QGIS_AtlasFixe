from PyPDF2 import PdfFileMerger, PdfFileReader
import os, glob

# à modifier en fonction du projet
dossier = r'd:\dossier\contenant\fichiers\a\fusionner' 
themeCarte = 'ZNS'
nbIdentifiantPerim = 5

# création d'un dossier de sortie nommé output
os.makedirs(dossier+r'\output', exist_ok=True)

# génération d'une liste contenant les noms des fichiers pdf
listPerim = []
listFichier = glob.glob(dossier+r"\*.pdf")
for item in listFichier :
    listPerim.append(os.path.basename(item)[0:nbIdentifiantPerim])
listPerim = list(set(listPerim))

# écriture des fichiers pdf fusionnés
os.chdir(input)
for item in listPerim :
    merger = PdfFileMerger()
    files = [x for x in os.listdir(input) if x.startswith(item) and x.endswith('.pdf')]
    for fname in sorted(files):
        with open(os.path.join(input, fname), 'rb') as f:
            merger.append(PdfFileReader(f))
    print(item)
    merger.write(dossier+r'\output\\'+item+themeCarte+'.pdf')