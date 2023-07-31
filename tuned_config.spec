{
    "profile": [
      {
        "data": "[main]\nsummary=Custom OpenShift profile\ninclude=openshift-node\n\n[sysctl]\nvm.${SYSTEM_KEY}=\"${RATIO}\"\n",
        "name": "tuned-profile-${TUNED_NAME}"
      }
    ],
    "recommend": [
      {
        "priority": 20,
        "profile": "tuned-profile-${TUNED_NAME}"
      }
    ]
}
