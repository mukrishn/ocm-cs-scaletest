{
    "profile": [
      {
        "data": "[main]\nsummary=Custom OpenShift profile\ninclude=openshift-node\n\n[sysctl]\n${SYSTEM_KEY}=\"${RATIO}\"\n",
        "name": "tuned-profile-${SYSTEM_KEY//_/}"
      }
    ],
    "recommend": [
      {
        "priority": 20,
        "profile": "tuned-profile-${SYSTEM_KEY//_/}"
      }
    ]
}
