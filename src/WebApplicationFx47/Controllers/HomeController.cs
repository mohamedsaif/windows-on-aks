using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;

namespace WebApplicationFx47.Controllers
{
    public class HomeController : Controller
    {
        public ActionResult Index()
        {
            ViewBag.Message = "System version 1";
            var daprSBKey = Environment.GetEnvironmentVariable("dapr-sb-key") ?? "NA";
            var daprStorageKey = Environment.GetEnvironmentVariable("dapr-storage-key");
            string daprSBKeyFile = "NA";
            if (System.IO.File.Exists(Server.MapPath("~/secrets/dapr-sb-key")))
                daprSBKeyFile = System.IO.File.ReadAllText(Server.MapPath("~/secrets/dapr-sb-key"));

            var message = $"System: Version 1.0 || Dapr SB Key: {daprSBKey} || Dapr Stg Key: {daprStorageKey} || Dapr SB File: {daprSBKeyFile}";
            ViewBag.Message = message;

            return View();
        }

        public ActionResult About()
        {
            ViewBag.Message = "Your application description page.";

            return View();
        }

        public ActionResult Contact()
        {
            ViewBag.Message = "Your contact page.";

            return View();
        }
    }
}