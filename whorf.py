from flask import Flask, request, jsonify
from os import environ, system
import logging
import json
import yaml
from datetime import datetime

webhook = Flask(__name__)

webhook.config['LABEL'] = environ.get('LABEL')

webhook.logger.setLevel(logging.INFO)


if "LABEL" not in environ:
    webhook.logger.error("Required environment variable for label isn't set. Exiting...")
    exit(1)


@webhook.route('/validate', methods=['POST'])
def validating_webhook():
    request_info = request.get_json()
    uid = request_info["request"].get("uid")

    ff = open('k8sobj.json', 'w+')
    yf = open('k8sobj.yaml', 'w+')
    json.dump(request_info, ff)
    yaml.dump(todict(request_info["request"]["object"]),yf)

    system('checkov --framework kubernetes -o json -f k8sobj.yaml > checkov.json')

    d = open('checkov.json','r')
    checkovresults = json.load(d)

    if checkovresults["summary"]["failed"] > 0:
        webhook.logger.error(f'Object {request_info["request"]["object"]["kind"]}/{request_info["request"]["object"]["metadata"]["name"]} failed security checks. Request rejected!')
        return admission_response(False, uid, f"Checkov found {checkovresults['summary']['failed']} issues in this manifest!")
    else:
        webhook.logger.info(f'Object {request_info["request"]["object"]["kind"]}/{request_info["request"]["object"]["metadata"]["name"]} passed security checks. Allowing the request.')
        return admission_response(True, uid, f"Checkov found {checkovresults['summary']['failed']} issues in this manifest! Congrats!")


def todict(obj):
    if hasattr(obj, 'attribute_map'):
        result = {}
        for k,v in getattr(obj, 'attribute_map').items():
            val = getattr(obj, k)
            if val is not None:
                result[v] = todict(val)
        return result
    elif type(obj) == list:
        return [todict(x) for x in obj]
    elif type(obj) == datetime:
        return str(obj)
    else:
        return obj


def admission_response(allowed, uid, message):
    return jsonify({"apiVersion": "admission.k8s.io/v1",
                    "kind": "AdmissionReview",
                    "response": {
                         "allowed": allowed,
                         "uid": uid,
                         "status": {
                           "code": 403,
                           "message": message
                         }
                       }
                    })


if __name__ == '__main__':
    webhook.run(host='0.0.0.0', port=1701)
