<%@ Page Language="C#" EnableSessionState="False" EnableViewState="False" %>
<%-- The one page for every PGPL ESS (hr.asaindia.org/pgpl) notification mail. mail_type says which mail it is.
     Mail building and sending: App_Code/EssMail.cs --%>
<script runat="server">
    protected void Page_Load(object sender, EventArgs e)
    {
        EssMail.HandleAny(this);
    }
</script>
