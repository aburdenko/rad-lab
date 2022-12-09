from flask import Flask, render_template
import subprocess
app = Flask(__name__)

app.config['TEMPLATES_AUTO_RELOAD'] = True

@app.route('/')
def home():
   return render_template('./main.html')


def run_command(command):
    import subprocess
    import shlex

    process = subprocess.Popen(shlex.split(command), stdout=subprocess.PIPE)
    while True:
        output = process.stdout.readline()
        output = str(output)
        if output == '' and process.poll() is not None:
            break
        if output:
            print (output.strip())
    rc = process.poll()
    return rc


@app.route('/alphafold')
def alpha_fold():
   cmd='python ../radlab' 
   run_command(cmd)
   return "installing Alphafold..."


if __name__ == '__main__':
   app.run()