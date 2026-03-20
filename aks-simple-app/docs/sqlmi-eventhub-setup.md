# SQL MI and Event Hubs setup

## What was added in the app

- `products-api` can read and write products from SQL Server when `PRODUCTS_SQL_CONNECTION_STRING` is set.
- `orders-api` can read and write orders from SQL Server when `ORDERS_SQL_CONNECTION_STRING` is set.
- `orders-api` publishes an `order-created` event to Event Hubs when `ORDERS_EVENTHUB_CONNECTION_STRING` and `ORDERS_EVENTHUB_NAME` are set.
- If those settings are not present, both APIs keep using the existing in-memory fallback.

## Kubernetes files

- `aks-simple-app/k8s/products-api.yaml`
- `aks-simple-app/k8s/orders-api.yaml`
- `aks-simple-app/k8s/app-data-secrets.example.yaml`

## To-do

1. Create a delegated subnet for SQL Managed Instance.
2. Create the SQL Managed Instance.
3. Create `productsdb` and `ordersdb`.
4. Create an Event Hubs namespace and an `orders-events` hub.
5. Create a send-only authorization rule for the event hub.
6. Create the Kubernetes secret from the generated connection strings.
7. Build and push updated images.
8. Deploy the updated manifests to AKS.
9. Test:
   - `GET /api/products/items`
   - `POST /api/products/items`
   - `GET /api/orders/status`
   - `POST /api/orders/orders`

## Azure CLI sample

Set variables:

```bash
RG="aks-learning-rg"
LOCATION="eastus"
VNET_NAME="aks-vnet"
SQLMI_SUBNET_NAME="sqlmi-subnet"
SQLMI_SUBNET_PREFIX="10.224.20.0/27"
SQLMI_NSG="sqlmi-nsg"
SQLMI_RT="sqlmi-rt"
SQLMI_NAME="aks-sqlmi"
SQLMI_ADMIN="sqladmin"
SQLMI_PASSWORD="ChangeMe123!"
EVENTHUB_NS="aks-learning-eh"
EVENTHUB_NAME="orders-events"
```

Create SQL MI subnet prerequisites:

```bash
az network nsg create -g $RG -n $SQLMI_NSG -l $LOCATION
az network route-table create -g $RG -n $SQLMI_RT -l $LOCATION
az network vnet subnet create \
  -g $RG \
  --vnet-name $VNET_NAME \
  -n $SQLMI_SUBNET_NAME \
  --address-prefixes $SQLMI_SUBNET_PREFIX \
  --delegations Microsoft.Sql/managedInstances \
  --network-security-group $SQLMI_NSG \
  --route-table $SQLMI_RT
```

Create SQL MI:

```bash
az sql mi create \
  -g $RG \
  -n $SQLMI_NAME \
  -l $LOCATION \
  --admin-user $SQLMI_ADMIN \
  --admin-password $SQLMI_PASSWORD \
  --subnet $SQLMI_SUBNET_NAME \
  --vnet-name $VNET_NAME \
  --capacity 4 \
  --storage 32GB \
  --family Gen5 \
  --license-type BasePrice
```

Create databases:

```bash
az sql midb create -g $RG --mi $SQLMI_NAME -n productsdb
az sql midb create -g $RG --mi $SQLMI_NAME -n ordersdb
```

Get SQL MI FQDN:

```bash
SQLMI_FQDN=$(az sql mi show -g $RG -n $SQLMI_NAME --query fullyQualifiedDomainName -o tsv)
echo $SQLMI_FQDN
```

Create Event Hubs namespace and hub:

```bash
az eventhubs namespace create \
  -g $RG \
  -n $EVENTHUB_NS \
  -l $LOCATION \
  --sku Basic \
  --capacity 1

az eventhubs eventhub create \
  -g $RG \
  --namespace-name $EVENTHUB_NS \
  -n $EVENTHUB_NAME \
  --partition-count 2 \
  --message-retention 1
```

Create send-only SAS rule and fetch connection string:

```bash
az eventhubs eventhub authorization-rule create \
  -g $RG \
  --namespace-name $EVENTHUB_NS \
  --eventhub-name $EVENTHUB_NAME \
  -n orders-sender \
  --rights Send

EVENTHUB_CONN=$(az eventhubs eventhub authorization-rule keys list \
  -g $RG \
  --namespace-name $EVENTHUB_NS \
  --eventhub-name $EVENTHUB_NAME \
  -n orders-sender \
  --query primaryConnectionString -o tsv)
```

Create the Kubernetes secret:

```bash
kubectl create secret generic app-data-secrets \
  -n aks-learning \
  --from-literal=products-sql-connection-string="Driver={ODBC Driver 18 for SQL Server};Server=tcp:${SQLMI_FQDN},1433;Database=productsdb;Uid=${SQLMI_ADMIN};Pwd=${SQLMI_PASSWORD};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;" \
  --from-literal=orders-sql-connection-string="Driver={ODBC Driver 18 for SQL Server};Server=tcp:${SQLMI_FQDN},1433;Database=ordersdb;Uid=${SQLMI_ADMIN};Pwd=${SQLMI_PASSWORD};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;" \
  --from-literal=orders-eventhub-connection-string="$EVENTHUB_CONN" \
  --from-literal=orders-eventhub-name="$EVENTHUB_NAME"
```

Deploy:

```bash
kubectl apply -f aks-simple-app/k8s/namespace.yaml
kubectl apply -f aks-simple-app/k8s/products-api.yaml
kubectl apply -f aks-simple-app/k8s/orders-api.yaml
kubectl apply -f aks-simple-app/k8s/frontend.yaml
```

## Cost note

`SQL Managed Instance` is not a low-cost service. The sample above uses a small General Purpose deployment, but it is still much more expensive than `Azure SQL Database` serverless.
If cost is the main requirement, use `Azure SQL Database` instead of `SQL MI`.
